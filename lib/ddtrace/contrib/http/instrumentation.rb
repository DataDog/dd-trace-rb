require 'uri'
require 'ddtrace/pin'
require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/contrib/analytics'

module Datadog
  module Contrib
    module HTTP
      # Instrumentation for Net::HTTP
      module Instrumentation
        def self.included(base)
          base.send(:prepend, InstanceMethods)
        end

        # Span hook invoked after request is completed.
        def self.after_request(&block)
          if block_given?
            # Set hook
            @after_request = block
          else
            # Get hook
            @after_request ||= nil
          end
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def request(req, body = nil, &block) # :yield: +response+
            pin = datadog_pin
            return super(req, body, &block) unless pin && pin.tracer

            if Datadog::Contrib::HTTP.should_skip_tracing?(req, @address, @port, pin.tracer)
              return super(req, body, &block)
            end

            pin.tracer.trace(Ext::SPAN_REQUEST, on_error: method(:annotate_span_with_error!)) do |span|
              begin
                span.service = pin.service
                span.span_type = Datadog::Ext::HTTP::TYPE_OUTBOUND
                span.resource = req.method

                if pin.tracer.enabled && !Datadog::Contrib::HTTP.should_skip_distributed_tracing?(pin)
                  Datadog::HTTPPropagator.inject!(span.context, req)
                end

                # Add additional request specific tags to the span.
                annotate_span_with_request!(span, req)
              rescue StandardError => e
                Datadog::Logger.log.error("error preparing span for http request: #{e}")
              ensure
                response = super(req, body, &block)
              end

              # Add additional response specific tags to the span.
              annotate_span_with_response!(span, response)

              # Invoke hook, if set.
              unless Contrib::HTTP::Instrumentation.after_request.nil?
                Contrib::HTTP::Instrumentation.after_request.call(span, self, req, response)
              end

              response
            end
          end

          def annotate_span_with_request!(span, request)
            span.set_tag(Datadog::Ext::HTTP::URL, request.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, request.method)

            if request.respond_to?(:uri) && request.uri
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, request.uri.host)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, request.uri.port.to_s)
            else
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, @address)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, @port.to_s)
            end

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?
          end

          def annotate_span_with_response!(span, response)
            return unless response && response.code

            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)

            case response.code.to_i
            when 400...599
              span.set_error(response)
            end
          end

          def annotate_span_with_error!(span, error)
            span.set_error(error)
          end

          def datadog_pin
            @datadog_pin ||= begin
              service = Datadog.configuration[:http][:service_name]
              tracer = Datadog.configuration[:http][:tracer]

              Datadog::Pin.new(service, app: Ext::APP, app_type: Datadog::Ext::AppTypes::WEB, tracer: tracer)
            end
          end

          private

          def datadog_configuration
            Datadog.configuration[:http]
          end

          def analytics_enabled?
            Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end
        end
      end
    end
  end
end
