require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/ext/http'
require 'ddtrace/contrib/grape/ext'
require 'ddtrace/contrib/status_code_matcher'

module Datadog
  module Contrib
    module Grape
      module Configuration
        # Custom settings for the Grape integration
        class Settings < Contrib::Configuration::Settings
          option :enabled do |o|
            o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            o.lazy
          end

          option :analytics_enabled do |o|
            o.default { env_to_bool([Ext::ENV_ANALYTICS_ENABLED, Ext::ENV_ANALYTICS_ENABLED_OLD], nil) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float([Ext::ENV_ANALYTICS_SAMPLE_RATE, Ext::ENV_ANALYTICS_SAMPLE_RATE_OLD], 1.0) }
            o.lazy
          end

          option :service_name, default: Ext::SERVICE_NAME

          option :error_statuses, default: nil do |o|
            o.setter do |new_value, _old_value|
              Datadog::Contrib::StatusCodeMatcher.new(new_value) unless new_value.nil?
            end
          end
        end
      end
    end
  end
end
