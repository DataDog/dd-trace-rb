require 'uri'
require 'ddtrace/pin'
require 'ddtrace/ext/app_types'

URL = 'elasticsearch.url'.freeze
METHOD = 'elasticsearch.method'.freeze
TOOK = 'elasticsearch.took'.freeze
PARAMS = 'elasticsearch.params'.freeze
BODY = 'elasticsearch.body'.freeze

DEFAULTSERVICE = 'elasticsearch'.freeze

module Datadog
  module Contrib
    module Elasticsearch
      # Elastic Search integration.
      module TracedClient
        def initialize(*args)
          pin = Datadog::Pin.new(DEFAULTSERVICE, app: 'elasticsearch', app_type: 'db')
          pin.onto(self)
          super(*args)
        end

        def perform_request(*args)
          pin = Datadog::Pin.get_from(self)
          method = args[0]
          full_url = URI.parse(args[1])

          stem = full_url.path
          params = full_url.query
          response = nil
          pin.tracer.trace('elasticsearch.query') do |span|
            span.service = pin.service
            span.span_type = Datadog::Ext::AppTypes::DB

            span.set_tag(METHOD, method)
            span.set_tag(URL, stem)
            span.set_tag(PARAMS, params)

            # TODO[Aaditya] set body as metadata on get request
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
