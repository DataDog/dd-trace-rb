# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    # Datadog Net/HTTP integration.
    module HTTP
      URL = 'http.url'.freeze
      METHOD = 'http.method'.freeze
      BODY = 'http.body'.freeze

      NAME = 'http.request'.freeze
      APP = 'net/http'.freeze
      SERVICE = 'net/http'.freeze

      module_function

      def should_skip_tracing?(req, address, port, transport, pin)
        # we don't want to trace our own call to the API (they use net/http)
        # when we know the host & port (from the URI) we use it, else (most-likely
        # called with a block) rely on the URL at the end.
        if req.respond_to?(:uri) && req.uri
          if req.uri.host.to_s == transport.hostname.to_s &&
             req.uri.port.to_i == transport.port.to_i
            return true
          end
        elsif address && port &&
              address.to_s == transport.hostname.to_s &&
              port.to_i == transport.port.to_i
          return true
        end
        # we don't want a "shotgun" effect with two nested traces for one
        # logical get, and request is likely to call itself recursively
        active = pin.tracer.active_span()
        return true if active && (active.name == NAME)
        false
      end

      def should_skip_distributed_tracing?(pin)
        if pin.config && pin.config.key?(:distributed_tracing)
          return !pin.config[:distributed_tracing]
        end

        !Datadog.configuration[:http][:distributed_tracing]
      end

      # Patcher enables patching of 'net/http' module.
      module Patcher
        include Base
        register_as :http, auto_patch: true
        option :distributed_tracing, default: false

        @patched = false

        module_function

        # patch applies our patch if needed
        def patch
          unless @patched
            begin
              require 'uri'
              require 'ddtrace/pin'
              require 'ddtrace/ext/app_types'
              require 'ddtrace/ext/http'
              require 'ddtrace/ext/net'
              require 'ddtrace/ext/distributed'

              patch_http()

              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply net/http integration: #{e}")
            end
          end
          @patched
        end

        # patched? tells wether patch has been successfully applied
        def patched?
          @patched
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/BlockLength
        # rubocop:disable Metrics/AbcSize
        def patch_http
          ::Net::HTTP.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Patcher.without_warnings do
              remove_method :initialize
            end

            def initialize(*args)
              pin = Datadog::Pin.new(SERVICE, app: APP, app_type: Datadog::Ext::AppTypes::WEB)
              pin.onto(self)
              initialize_without_datadog(*args)
            end

            alias_method :request_without_datadog, :request
            remove_method :request

            def request(req, body = nil, &block) # :yield: +response+
              pin = Datadog::Pin.get_from(self)
              return request_without_datadog(req, body, &block) unless pin && pin.tracer

              transport = pin.tracer.writer.transport
              return request_without_datadog(req, body, &block) if
                Datadog::Contrib::HTTP.should_skip_tracing?(req, @address, @port, transport, pin)

              pin.tracer.trace(NAME) do |span|
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
                  span.set_error(response)
                when 5
                  span.set_error(response)
                end

                response
              end
            end
          end
        end
      end
    end
  end
end
