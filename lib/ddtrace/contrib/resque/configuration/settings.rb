require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/resque/ext'

module Datadog
  module Contrib
    module Resque
      module Configuration
        # Custom settings for the Resque integration
        class Settings < Contrib::Configuration::Settings
          option :enabled do |o|
            o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            o.lazy
          end

          option :analytics_enabled do |o|
            o.default { env_to_bool([Ext::ENV_ANALYTICS_ENABLED, Ext::ENV_ANALYTICS_ENABLED_OLD], false) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float([Ext::ENV_ANALYTICS_SAMPLE_RATE, Ext::ENV_ANALYTICS_SAMPLE_RATE_OLD], 1.0) }
            o.lazy
          end

          option :service_name, default: Ext::SERVICE_NAME

          # TODO: 1.0: When moving to auto patching all workers by default
          # we should remove this setting, as it will be a no-op.
          option :workers, default: []
          option :error_handler, default: Datadog::Tracer::DEFAULT_ON_ERROR

          # TODO: 1.0: Automatic patching should be the default behavior.
          # We should not provide this option anymore when making it the default,
          # as our integrations should always instrument all possible scenarios when feasible.
          option :auto_instrument, default: false
        end
      end
    end
  end
end
