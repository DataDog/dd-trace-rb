module Datadog
  module Tracing
    module Contrib
      module Opensearch
        # Opensearch integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_OPENSEARCH_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_OPENSEARCH_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_OPENSEARCH_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_OPENSEARCH_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'opensearch'.freeze
          SPAN_QUERY = 'opensearch.query'.freeze
          SPAN_TYPE_QUERY = 'opensearch'.freeze
          TAG_BODY = 'opensearch.body'.freeze
          TAG_METHOD = 'opensearch.method'.freeze
          TAG_PARAMS = 'opensearch.params'.freeze
          TAG_URL = 'opensearch.url'.freeze
          TAG_COMPONENT = 'opensearch'.freeze
          TAG_OPERATION_QUERY = 'query'.freeze

          TAG_SYSTEM = 'opensearch'.freeze
        end
      end
    end
  end
end
