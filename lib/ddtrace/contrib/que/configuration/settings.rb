# typed: false
# frozen_string_literal: true

require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Que
      module Configuration
        # Default settings for the Que integration
        class Settings < Datadog::Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
          option :distributed_tracing, default: true

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

          option :tag_args do |o|
            o.default { env_to_bool(Ext::ENV_TAG_ARGS_ENABLED, false) }
            o.lazy
          end

          option :tag_data do |o|
            o.default { env_to_bool(Ext::ENV_TAG_DATA_ENABLED, false) }
            o.lazy
          end
          option :error_handler, default: Datadog::SpanOperation::Events::DEFAULT_ON_ERROR
        end
      end
    end
  end
end
