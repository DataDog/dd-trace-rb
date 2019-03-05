require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/http/ext'

module Datadog
  module Contrib
    # Datadog Net/HTTP integration.
    module HTTP
      # Patcher enables patching of 'net/http' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:http)
        end

        # patch applies our patch if needed
        def patch
          do_once(:http) do
            begin
              require 'uri'
              require 'ddtrace/pin'
              require 'ddtrace/ext/app_types'
              require 'ddtrace/ext/errors'
              require 'ddtrace/ext/http'
              require 'ddtrace/ext/net'
              require 'ddtrace/ext/distributed'

              patch_http
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply net/http integration: #{e}")
            end
          end
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/BlockLength
        # rubocop:disable Metrics/AbcSize
        def patch_http
          ::Net::HTTP.class_eval do
            alias_method :request_without_datadog, :request
            remove_method :request

            def datadog_pin
              @datadog_pindatadog_pin ||= begin
                service = Datadog.configuration[:http][:service_name]
                tracer = Datadog.configuration[:http][:tracer]

                Datadog::Pin.new(service, app: Ext::APP, app_type: Datadog::Ext::AppTypes::WEB, tracer: tracer)
              end
            end

            def request(req, body = nil, &block) # :yield: +response+
              pin = datadog_pin
              return request_without_datadog(req, body, &block) unless pin && pin.tracer

              transport = pin.tracer.writer.transport

              if Datadog::Contrib::HTTP.should_skip_tracing?(req, @address, @port, transport, pin)
                return request_without_datadog(req, body, &block)
              end

              pin.tracer.trace(Ext::SPAN_REQUEST) do |span|
                begin
                  span.service = pin.service
                  span.span_type = Datadog::Ext::HTTP::TYPE

                  span.resource = req.method
                  # Using the method as a resource, as URL/path can trigger
                  # a possibly infinite number of resources.
                  span.set_tag(Datadog::Ext::HTTP::URL, req.path)
                  span.set_tag(Datadog::Ext::HTTP::METHOD, req.method)

                  if pin.tracer.enabled && !Datadog::Contrib::HTTP.should_skip_distributed_tracing?(pin)
                    req.add_field(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID, span.trace_id)
                    req.add_field(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID, span.span_id)
                    if span.context.sampling_priority
                      req.add_field(
                        Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY,
                        span.context.sampling_priority
                      )
                    end
                  end
                rescue StandardError => e
                  Datadog::Tracer.log.error("error preparing span for http request: #{e}")
                ensure
                  response = request_without_datadog(req, body, &block)
                end
                span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)
                if req.respond_to?(:uri) && req.uri
                  span.set_tag(Datadog::Ext::NET::TARGET_HOST, req.uri.host)
                  span.set_tag(Datadog::Ext::NET::TARGET_PORT, req.uri.port.to_s)
                else
                  span.set_tag(Datadog::Ext::NET::TARGET_HOST, @address)
                  span.set_tag(Datadog::Ext::NET::TARGET_PORT, @port.to_s)
                end

                case response.code.to_i / 100
                when 4
                  set_response_as_span_error(span, response)
                when 5
                  set_response_as_span_error(span, response)
                end

                response
              end
            end

            def set_response_as_span_error(span, response)
              return if response.nil?
              span.status = Datadog::Ext::Errors::STATUS
              span.set_tag(Datadog::Ext::Errors::TYPE, response.class)
              span.set_tag(Datadog::Ext::Errors::MSG, response.body) if response.respond_to?(:body)
            end
          end
        end
      end
    end
  end
end
