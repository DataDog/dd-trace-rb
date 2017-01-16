require 'uri'
require 'ddtrace/pin'
require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    module HTTP
      URL = 'http.url'.freeze
      METHOD = 'http.method'.freeze
      BODY = 'http.body'.freeze

      NAME = 'http.request'.freeze
      SERVICE = 'http'.freeze
      SPAN_TYPE = 'http'.freeze

      # Datadog APM Net/HTTP integration.
      module TracedHTTP
        def initialize(*args)
          pin = Datadog::Pin.new(SERVICE, app: 'nethttp', app_type: Datadog::Ext::AppTypes::DB)
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
            span.span_type = SPAN_TYPE

            span.set_tag(METHOD, req.method)
            span.set_tag(URL, req.path)

            span.resource = "#{req.method} #{req.path}"

            return super(req, body, &block)
          end
        end
      end
    end
  end
end
