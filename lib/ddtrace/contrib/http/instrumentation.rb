# typed: false
require 'uri'
require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/ext/metadata'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/http_annotation_helper'

module Datadog
  module Contrib
    module HTTP
      # Instrumentation for Net::HTTP
      module Instrumentation
        def self.included(base)
          base.prepend(InstanceMethods)
        end

        # Span hook invoked after request is completed.
        def self.after_request(&block)
          if block
            # Set hook
            @after_request = block
          else
            # Get hook
            @after_request ||= nil
          end
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          include Datadog::Contrib::HttpAnnotationHelper

          # :yield: +response+
          def request(req, body = nil, &block)
            host, = host_and_port(req)
            request_options = datadog_configuration(host)
            client_config = Datadog::Tracing.configuration_for(self)

            return super(req, body, &block) if Datadog::Contrib::HTTP.should_skip_tracing?(req)

            Datadog::Tracing.trace(Ext::SPAN_REQUEST, on_error: method(:annotate_span_with_error!)) do |span, trace|
              begin
                span.service = service_name(host, request_options, client_config)
                span.span_type = Datadog::Ext::HTTP::TYPE_OUTBOUND
                span.resource = req.method

                if Datadog::Tracing.enabled? && !Datadog::Contrib::HTTP.should_skip_distributed_tracing?(client_config)
                  Datadog::HTTPPropagator.inject!(trace, req)
                end

                # Add additional request specific tags to the span.
                annotate_span_with_request!(span, req, request_options)
              rescue StandardError => e
                Datadog.logger.error("error preparing span for http request: #{e}")
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

          def annotate_span_with_request!(span, request, request_options)
            span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_REQUEST)

            span.set_tag(Datadog::Ext::HTTP::URL, request.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, request.method)

            host, port = host_and_port(request)
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, host)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, port.to_s)

            # Tag as an external peer service
            span.set_tag(Datadog::Ext::Metadata::TAG_PEER_SERVICE, span.service)
            span.set_tag(Datadog::Ext::Metadata::TAG_PEER_HOSTNAME, host)

            # Set analytics sample rate
            set_analytics_sample_rate(span, request_options)
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

          def set_analytics_sample_rate(span, request_options)
            return unless analytics_enabled?(request_options)

            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate(request_options))
          end

          private

          def host_and_port(request)
            if request.respond_to?(:uri) && request.uri
              [request.uri.host, request.uri.port]
            else
              [@address, @port]
            end
          end

          def datadog_configuration(host = :default)
            Datadog::Tracing.configuration[:http, host]
          end

          def analytics_enabled?(request_options)
            Contrib::Analytics.enabled?(request_options[:analytics_enabled])
          end

          def analytics_sample_rate(request_options)
            request_options[:analytics_sample_rate]
          end
        end
      end
    end
  end
end
