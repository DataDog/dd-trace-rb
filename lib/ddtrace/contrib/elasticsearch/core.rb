require 'uri'
require 'ddtrace/pin'
require 'ddtrace/ext/app_types'
require 'json'

module Datadog
  module Contrib
    module Elasticsearch
      URL = 'elasticsearch.url'.freeze
      METHOD = 'elasticsearch.method'.freeze
      PARAMS = 'elasticsearch.params'.freeze
      BODY = 'elasticsearch.body'.freeze

      DEFAULTSERVICE = 'elasticsearch'.freeze
      SPAN_TYPE = 'elasticsearch'.freeze

      # Datadog APM Elastic Search integration.
      module TracedClient
        def initialize(*args)
          pin = Datadog::Pin.new(DEFAULTSERVICE, app: 'elasticsearch', app_type: Datadog::Ext::AppTypes::DB)
          pin.onto(self)
          super(*args)
        end

        def perform_request(*args)
          pin = Datadog::Pin.get_from(self)
          method = args[0]
          path = args[1]
          params = args[2]
          body = args[3]
          full_url = URI.parse(path)

          stem = full_url.path
          response = nil
          pin.tracer.trace(pin.name ? pin.name : 'elasticsearch.query') do |span|
            span.service = pin.service
            span.span_type = SPAN_TYPE

            span.set_tag(METHOD, method)
            span.set_tag(URL, stem)
            span.set_tag(PARAMS, JSON.generate(params)) if params
            span.set_tag(BODY, JSON.generate(body)) if body

            # TODO[Aaditya] properly quantize resource
            span.resource = "#{method} #{stem}"

            response = super(*args)
          end

          response
        end
      end
    end
  end
end

module Elasticsearch
  module Transport
    # Auto-patching of Transport::Client with our tracing wrappers.
    class Client
      prepend Datadog::Contrib::Elasticsearch::TracedClient
    end
  end
end
