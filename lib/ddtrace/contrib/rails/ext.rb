module Datadog
  module Contrib
    module Rails
      # Rails integration constants
      module Ext
        APP = 'rails'.freeze
        ENV_ENABLED = 'DD_TRACE_RAILS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_RAILS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_RAILS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_RAILS_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_RAILS_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_DISABLE = 'DISABLE_DATADOG_RAILS'.freeze
        ENV_LOGS_INJECTION_ENABLED = 'DD_LOGS_INJECTION'.freeze
      end
    end
  end
end
