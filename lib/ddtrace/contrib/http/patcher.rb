# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module HTTP
      URL = 'http.url'.freeze
      METHOD = 'http.method'.freeze
      BODY = 'http.body'.freeze

      NAME = 'http.request'.freeze
      APP = 'net/http'.freeze
      SERVICE = 'net/http'.freeze

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
              require 'ddtrace/ext/app_types'
              require 'ddtrace/ext/http'

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

        # rubocop:disable Metrics/CyclomaticComplexity
        def patch_http
          ::Net::HTTP.class_eval do
            alias_method :initialize_without_datadog, :initialize
            remove_method :initialize

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

              # we don't want to trace our own call to the API (they use net/http)
              path = req.path.to_s
              return request_without_datadog(req, body, &block) if
                path.end_with?(pin.tracer.writer.transport.traces_endpoint) ||
                path.end_with?(pin.tracer.writer.transport.services_endpoint)

              # we don't want a "shotgun" effect with two nested traces for one
              # logical get, and request is likely to call itself recursively
              active = pin.tracer.active_span()
              return request_without_datadog(req, body, &block) if active && (active.name == NAME)

              pin.tracer.trace(NAME) do |span|
                span.service = pin.service
                span.span_type = Datadog::Ext::HTTP::TYPE

                span.resource = path
                # *NOT* filling Datadog::Ext::HTTP::URL as it's already in resource.
                # The agent can then decide to quantize the URL and store the original,
                # untouched data in http.url but the client should not send redundant fields.
                span.set_tag(Datadog::Ext::HTTP::METHOD, req.method)
                response = request_without_datadog(req, body, &block)
                span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)

                response
              end
            end
          end
        end
      end
    end
  end
end
