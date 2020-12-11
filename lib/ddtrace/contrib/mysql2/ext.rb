module Datadog
  module Contrib
    module Mysql2
      # Mysql2 integration constants
      module Ext
        APP = 'mysql2'.freeze
        ENV_ENABLED = 'DD_TRACE_MYSQL2_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_MYSQL2_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_MYSQL2_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_MYSQL2_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_MYSQL2_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'mysql2'.freeze
        SPAN_QUERY = 'mysql2.query'.freeze
        TAG_DB_NAME = 'mysql2.db.name'.freeze
      end
    end
  end
end
