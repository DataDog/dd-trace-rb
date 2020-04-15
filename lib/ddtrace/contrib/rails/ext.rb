module Datadog
  module Contrib
    module Rails
      # Rails integration constants
      module Ext
        APP = 'rails'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_RAILS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_RAILS_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_DISABLE = 'DISABLE_DATADOG_RAILS'.freeze
      end
    end
  end
end
