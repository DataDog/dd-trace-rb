# typed: false
require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/delayed_job/ext'

module Datadog
  module Contrib
    module DelayedJob
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
          option :client_service_name, default: Ext::CLIENT_SERVICE_NAME
          option :error_handler, default: Datadog::SpanOperation::Events::DEFAULT_ON_ERROR
        end
      end
    end
  end
end
