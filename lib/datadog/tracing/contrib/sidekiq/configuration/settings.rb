# frozen_string_literal: true

require_relative '../../../span_operation'
require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Sidekiq
        module Configuration
          # Custom settings for the Sidekiq integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.env_var Ext::ENV_ENABLED
              o.default true
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :analytics_enabled do |o|
              o.env_var Ext::ENV_ANALYTICS_ENABLED
              o.default false
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :analytics_sample_rate do |o|
              o.env_var Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
              o.setter do |value|
                val_to_float(value)
              end
            end

            option :tag_args do |o|
              o.env_var Ext::ENV_TAG_JOB_ARGS
              o.default false
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :service_name
            option :client_service_name
            option :error_handler, experimental_default_proc: Tracing::SpanOperation::Events::DEFAULT_ON_ERROR
            option :quantize, default: {}
            option :distributed_tracing, default: false
          end
        end
      end
    end
  end
end
