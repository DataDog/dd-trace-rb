require 'uri'
require 'ddtrace/pin'
require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'

module Datadog
  module Contrib
    module HTTP
      URL = 'http.url'.freeze
      METHOD = 'http.method'.freeze
      BODY = 'http.body'.freeze

      NAME = 'http.request'.freeze
      APP = 'net/http'.freeze
      SERVICE = 'net/http'.freeze

      # Datadog APM Net/HTTP integration.
      module TracedHTTP
        def initialize(*args)
          pin = Datadog::Pin.new(SERVICE, app: APP, app_type: Datadog::Ext::AppTypes::WEB)
          pin.onto(self)
          super(*args)
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        def request(req, body = nil, &block) # :yield: +response+
          # we don't want to trace our own call to the API (they use net/http)
          path = req.path.to_s
          return super(req, body, &block) if path.end_with?(pin.tracer.writer.transport.traces_endpoint) ||
                                             path.end_with?(pin.tracer.writer.transport.services_endpoint)

          pin = Datadog::Pin.get_from(self)
          return super(req, body, &block) unless pin && pin.tracer

          # we don't want a "shotgun" effect with two nested traces for one
          # logical get, and request is likely to call itself recursively
          active = pin.tracer.active_span()
          return super(req, body, &block) if active && (active.name == NAME)

          pin.tracer.trace(NAME) do |span|
            span.service = pin.service
            span.span_type = Datadog::Ext::HTTP::TYPE

            span.resource = path
            # *NOT* filling Datadog::Ext::HTTP::URL as it's already in resource.
            # The agent can then decide to quantize the URL and store the original,
            # untouched data in http.url but the client should not send redundant fields.
            span.set_tag(Datadog::Ext::HTTP::METHOD, req.method)
            response = super(req, body, &block)
            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)

            response
          end
        end
      end
    end
  end
end
