# typed: false
require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/active_job/ext'

module Datadog
  module Contrib
    module ActiveJob
      module Configuration
        # Custom settings for the DelayedJob integration
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
          option :error_handler, default: Datadog::Tracer::DEFAULT_ON_ERROR

          DEPRECATION_WARN_ONLY_ONCE_TRUE = Datadog::Utils::OnlyOnce.new
          DEPRECATION_WARN_ONLY_ONCE_FALSE = Datadog::Utils::OnlyOnce.new

          option :log_injection do |o|
            o.delegate_to { Datadog.configuration.log_injection }
            o.lazy
            o.on_set do |value|
              if value
                DEPRECATION_WARN_ONLY_ONCE_TRUE.run do
                  Datadog.logger.warn(
                    "log_injection is now a global option that defaults to `true`\n" \
                    "and can't be configured on per-integration basis.\n" \
                    'Please remove the `log_injection` setting from `c.use :active_job, log_injection: ...`.'
                  )
                end
              else
                DEPRECATION_WARN_ONLY_ONCE_FALSE.run do
                  Datadog.logger.warn(
                    "log_injection is now a global option that defaults to `true`\n" \
                    "and can't be configured on per-integration basis.\n" \
                    'Please remove the `log_injection` setting from `c.use :active_job, log_injection: ...` and use ' \
                    "`Datadog.configure { |c| c.log_injection = false }` if you wish to disable it.\n"
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end
