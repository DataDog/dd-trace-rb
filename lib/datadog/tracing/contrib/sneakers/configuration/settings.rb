# frozen_string_literal: true

require_relative '../../../span_operation'
require_relative '../../configuration/settings'

module Datadog
  module Tracing
    module Contrib
      module Sneakers
        module Configuration
          # Default settings for the Shoryuken integration
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end

            option :analytics_enabled do |o|
              o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
              o.lazy
            end

            option :analytics_sample_rate do |o|
              o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
              o.lazy
            end

            option :service_name
            option :error_handler, default: Tracing::SpanOperation::Events::DEFAULT_ON_ERROR
            option :tag_body, default: false
          end
        end
      end
    end
  end
end
