# typed: false
require 'datadog/tracing/span_operation'
require 'datadog/tracing/contrib/configuration/settings'
require 'datadog/tracing/contrib/sidekiq/ext'

module Datadog
  module Tracing
    module Contrib
      module Sidekiq
        module Configuration
          # Custom settings for the Sidekiq integration
          # @public_api
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

            option :tag_args do |o|
              o.default { env_to_bool(Ext::ENV_TAG_JOB_ARGS, false) }
              o.lazy
            end

            option :service_name
            option :client_service_name
            option :error_handler, default: Tracing::SpanOperation::Events::DEFAULT_ON_ERROR
          end
        end
      end
    end
  end
end
