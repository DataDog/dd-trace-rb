# typed: true
module Datadog
  module Contrib
    module Mysql2
      # Mysql2 integration constants
      module Ext
        ENV_ENABLED = 'DD_TRACE_MYSQL2_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_MYSQL2_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_MYSQL2_ANALYTICS_SAMPLE_RATE'.freeze
        DEFAULT_PEER_SERVICE_NAME = 'mysql2'.freeze
        SPAN_QUERY = 'mysql2.query'.freeze
        TAG_DB_NAME = 'mysql2.db.name'.freeze
        TAG_COMPONENT = 'mysql2'.freeze
        TAG_OPERATION_QUERY = 'query'.freeze
      end
    end
  end
end
