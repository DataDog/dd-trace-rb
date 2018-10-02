module Datadog
  module Contrib
    module Elasticsearch
      # Elasticsearch integration constants
      module Ext
        APP = 'elasticsearch'.freeze
        SERVICE_NAME = 'elasticsearch'.freeze

        SPAN_QUERY = 'elasticsearch.query'.freeze

        TAG_BODY = 'elasticsearch.body'.freeze
        TAG_METHOD = 'elasticsearch.method'.freeze
        TAG_PARAMS = 'elasticsearch.params'.freeze
        TAG_URL = 'elasticsearch.url'.freeze
      end
    end
  end
end
