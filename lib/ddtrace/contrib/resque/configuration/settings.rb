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

          # A list Ruby worker classes to be instrumented.
          # The value of `nil` has special semantics: it instruments all workers dynamically.
          #
          # TODO: 1.0: Automatic patching should be the default behavior.
          # We should not provide this option in the future,
          # as our integrations should always instrument all possible scenarios when feasible.
          option :workers, default: nil do |o|
            o.on_set do |value|
              unless value.nil?
                Datadog.logger.warn(
                  "DEPRECATED: Resque integration now instruments all workers. \n" \
                  'The `workers:` option is unnecessary and will be removed in the future.'
                )
              end
            end
          end
          option :error_handler, default: Datadog::Tracer::DEFAULT_ON_ERROR
        end
      end
    end
  end
end
