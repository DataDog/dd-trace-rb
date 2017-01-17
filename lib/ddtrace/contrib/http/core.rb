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

        def request(req, body = nil, &block) # :yield: +response+
          pin = Datadog::Pin.get_from(self)
          return super(req, body, &block) unless pin && pin.tracer

          # Request calls itself in some cases. We don't want a "shotgun effect" and
          # trace one logical call twice, so if we detect NAME is calling NAME,
          # we only keep the outer, encapsulating call.
          active = pin.tracer.active_span()
          return super(req, body, &block) if active && (active.name == NAME)

          pin.tracer.trace(NAME) do |span|
            span.service = pin.service
            span.span_type = Datadog::Ext::HTTP::TYPE

            span.resource = req.path
            # *NOT* filling Datadog::Ext::HTTP::URL as it's already in resource.
            # The agent can then decide to quantize the URL and store the original,
            # untouched data in http.url but the client should not send redundant fields.
            span.set_tag(Datadog::Ext::HTTP::METHOD, req.method)
            response = super(req, body, &block)
            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)

            return response
          end
        end
      end
    end
  end
end
