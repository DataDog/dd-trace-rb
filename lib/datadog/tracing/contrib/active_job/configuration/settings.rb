# frozen_string_literal: true

require_relative '../../../span_operation'
require_relative '../ext'
require_relative '../../configuration/settings'

module Datadog
  module Tracing
    module Contrib
      module ActiveJob
        module Configuration
          # Custom settings for the DelayedJob integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            end

            option :analytics_enabled do |o|
              o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
            end

            option :analytics_sample_rate do |o|
              o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
            end

            option :service_name
            option :error_handler, experimental_default_proc: Tracing::SpanOperation::Events::DEFAULT_ON_ERROR
          end
        end
      end
    end
  end
end
