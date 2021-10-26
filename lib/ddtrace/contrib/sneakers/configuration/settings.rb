# typed: false
# frozen_string_literal: true

require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Sneakers
      module Configuration
        # Default settings for the Shoryuken integration
        class Settings < Datadog::Contrib::Configuration::Settings
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
          option :error_handler, default: Datadog::SpanOperation::Events::DEFAULT_ON_ERROR
          option :tag_body, default: false
        end
      end
    end
  end
end
