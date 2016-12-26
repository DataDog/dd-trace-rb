require 'uri'
require 'ddtrace/pin'
require 'ddtrace/ext/app_types'
require 'json'
require 'ddtrace/contrib/elasticsearch/quantize'

module Datadog
  module Contrib
    module Elasticsearch
      URL = 'elasticsearch.url'.freeze
      METHOD = 'elasticsearch.method'.freeze
      PARAMS = 'elasticsearch.params'.freeze
      BODY = 'elasticsearch.body'.freeze

      SERVICE = 'elasticsearch'.freeze
      SPAN_TYPE = 'elasticsearch'.freeze

      # Datadog APM Elastic Search integration.
      module TracedClient
        def initialize(*args)
          pin = Datadog::Pin.new(SERVICE, app: 'elasticsearch', app_type: Datadog::Ext::AppTypes::DB)
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

          url = full_url.path
          response = nil
          pin.tracer.trace('elasticsearch.query') do |span|
            span.service = pin.service
            span.span_type = SPAN_TYPE

            span.set_tag(METHOD, method)
            span.set_tag(URL, url)
            span.set_tag(PARAMS, JSON.generate(params)) if params
            span.set_tag(BODY, JSON.generate(body)) if body

            quantized_url = Datadog::Contrib::Elasticsearch::Quantize.format_url(url)
            span.resource = "#{method} #{quantized_url}"

            response = super(*args)
          end

          response
        end
      end
    end
  end
end
