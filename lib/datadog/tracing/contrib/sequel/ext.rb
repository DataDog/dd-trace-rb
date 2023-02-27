module Datadog
  module Tracing
    module Contrib
      module Sequel
        # Sequel integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_SEQUEL_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_SEQUEL_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SEQUEL_ANALYTICS_SAMPLE_RATE'.freeze
          SPAN_QUERY = 'sequel.query'.freeze
          TAG_DB_VENDOR = 'sequel.db.vendor'.freeze
          TAG_PREPARED_NAME = 'sequel.prepared.name'.freeze
          TAG_COMPONENT = 'sequel'.freeze
          TAG_OPERATION_QUERY = 'query'.freeze
        end
      end
    end
  end
end
