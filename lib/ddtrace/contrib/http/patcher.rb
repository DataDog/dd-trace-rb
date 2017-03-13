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

      # Patcher enables patching of 'net/http' module.
      # This is used in monkey.rb to automatically apply patches
      module Patcher
        @patched = false

        module_function

        # patch applies our patch if needed
        def patch
          unless @patched
            begin
              require 'uri'
              require 'ddtrace/pin'
              require 'ddtrace/monkey'
              require 'ddtrace/ext/app_types'
              require 'ddtrace/ext/http'
              require 'ddtrace/ext/net'

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
        def patch_http
          ::Net::HTTP.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Monkey.without_warnings do
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
                span.service = pin.service
                span.span_type = Datadog::Ext::HTTP::TYPE

                span.resource = req.path
                # *NOT* filling Datadog::Ext::HTTP::URL as it's already in resource.
                # The agent can then decide to quantize the URL and store the original,
                # untouched data in http.url but the client should not send redundant fields.
                span.set_tag(Datadog::Ext::HTTP::METHOD, req.method)
                response = request_without_datadog(req, body, &block)
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
