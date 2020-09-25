module Datadog
  module Contrib
    module Sequel
      # Sequel integration constants
      module Ext
        APP = 'sequel'.freeze
        ENV_ENABLED = 'DD_TRACE_SEQUEL_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_SEQUEL_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_SEQUEL_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SEQUEL_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_SEQUEL_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'sequel'.freeze
        SPAN_QUERY = 'sequel.query'.freeze
        TAG_DB_VENDOR = 'sequel.db.vendor'.freeze
        TAG_PREPARED_NAME = 'sequel.prepared.name'.freeze
      end
    end
  end
end
