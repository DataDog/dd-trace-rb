require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/cucumber/ext'

module Datadog
  module Contrib
    module Cucumber
      module Configuration
        # Custom settings for the Cucumber integration
        class Settings < Contrib::Configuration::Settings
          option :enabled do |o|
            o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            o.lazy
          end

          option :analytics_enabled do |o|
            o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, true) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
            o.lazy
          end

          # TODO: shall we enable the distributed tracing globally?
          # option :distributed_tracing, default: true
        end
      end
    end
  end
end
