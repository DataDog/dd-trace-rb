module Datadog
  module Contrib
    module Presto
      # Presto integration constants
      module Ext
        APP = 'presto'.freeze
        ENV_ENABLED = 'DD_TRACE_PRESTO_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_PRESTO_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_PRESTO_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_PRESTO_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_PRESTO_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'presto'.freeze
        SPAN_QUERY = 'presto.query'.freeze
        SPAN_RESUME = 'presto.resume_query'.freeze
        SPAN_KILL = 'presto.kill_query'.freeze
        TAG_SCHEMA_NAME = 'presto.schema'.freeze
        TAG_CATALOG_NAME = 'presto.catalog'.freeze
        TAG_USER_NAME = 'presto.user'.freeze
        TAG_TIME_ZONE = 'presto.time_zone'.freeze
        TAG_LANGUAGE = 'presto.language'.freeze
        TAG_PROXY = 'presto.http_proxy'.freeze
        TAG_MODEL_VERSION = 'presto.model_version'.freeze
        TAG_QUERY_ID = 'presto.query.id'.freeze
        TAG_QUERY_ASYNC = 'presto.query.async'.freeze
      end
    end
  end
end
