module Datadog
  module Contrib
    module Sequel
      # Sequel integration constants
      module Ext
        APP = 'sequel'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_SEQUEL_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_SEQUEL_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'sequel'.freeze
        SPAN_QUERY = 'sequel.query'.freeze
        TAG_DB_VENDOR = 'sequel.db.vendor'.freeze
      end
    end
  end
end
