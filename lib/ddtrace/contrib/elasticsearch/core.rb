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
        def initialize(*)
          pin = Datadog::Pin.new(SERVICE, app: 'elasticsearch', app_type: Datadog::Ext::AppTypes::DB)
          pin.onto(self)
          super
        end

        def perform_request(*args)
          pin = Datadog::Pin.get_from(self)
          return super unless pin && pin.tracer

          method = args[0]
          path = args[1]
          params = args[2]
          body = args[3]
          full_url = URI.parse(path)

          url = full_url.path
          response = nil
          pin.tracer.trace('elasticsearch.query') do |span|
            begin
              span.service = pin.service
              span.span_type = SPAN_TYPE

              # load JSON for the following fields unless they're already strings
              params = JSON.generate(params) if params && !params.is_a?(String)
              body = JSON.generate(body) if body && !body.is_a?(String)

              span.set_tag(METHOD, method)
              span.set_tag(URL, url)
              span.set_tag(PARAMS, params) if params
              span.set_tag(BODY, body) if body

              quantized_url = Datadog::Contrib::Elasticsearch::Quantize.format_url(url)
              span.resource = "#{method} #{quantized_url}"
            rescue StandardError => e
              Datadog::Tracer.log.error(e.message)
            ensure
              # the call is still executed
              response = super(*args)
            end
          end
          response
        end
      end
    end
  end
end
