require 'uri'
require 'ddtrace'
require 'ddtrace/ext/app_types'
require 'elasticsearch/transport'

URL = 'elasticsearch.url'
METHOD = 'elasticsearch.method'
TOOK = 'elasticsearch.took'
PARAMS = 'elasticsearch.params'
BODY = 'elasticsearch.body'

module Datadog
  module Contrib
    module Elasticsearch
      module TracedClient
        def perform_request(*args)
          method = args[0]
          full_url = URI.parse(args[1])

          stem, params = full_url.path, full_url.query
          response = nil
          tracer = Datadog.tracer
          tracer.trace('elasticsearch.query') do |span|
            span.service = "FIXME"
            span.span_type = Datadog::Ext::AppTypes::DB

            span.set_tag(METHOD, method)
            span.set_tag(URL, stem)
            span.set_tag(PARAMS, params)

            #TODO[Aaditya] set body as metadata on get request
            #TODO[Aaditya] properly quantize resource

            response = super(*args)
          end

          return response
        end
      end
    end
  end
end

module Elasticsearch
  module Transport
    class Client
      prepend Datadog::Contrib::Elasticsearch::TracedClient
    end
  end
end
