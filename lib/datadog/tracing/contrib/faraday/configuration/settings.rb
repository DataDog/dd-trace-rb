require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Faraday
        module Configuration
          # Custom settings for the Faraday integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            DEFAULT_ERROR_HANDLER = lambda do |env|
              Tracing::Metadata::Ext::HTTP::ERROR_RANGE.cover?(env[:status])
            end

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

            option :distributed_tracing, default: true
            option :error_handler, default: DEFAULT_ERROR_HANDLER
            option :split_by_domain, default: false

            option :service_name do |o|
              o.default { ENV.fetch(Ext::ENV_SERVICE_NAME, Ext::DEFAULT_PEER_SERVICE_NAME) }
              o.lazy
            end
          end
        end
      end
    end
  end
end
