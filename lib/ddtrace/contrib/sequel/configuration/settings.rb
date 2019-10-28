require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/sequel/ext'

module Datadog
  module Contrib
    module Sequel
      module Configuration
        # Custom settings for the Sequel integration
        class Settings < Contrib::Configuration::Settings
          option :analytics_enabled do |o|
            o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
            o.lazy
          end
        end
      end
    end
  end
end
