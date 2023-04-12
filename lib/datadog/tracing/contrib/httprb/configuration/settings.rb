require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Httprb
        module Configuration
          # Custom settings for the Httprb integration
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

            option :distributed_tracing, default: true

            option :service_name do |o|
              o.default { ENV.fetch(Ext::ENV_SERVICE_NAME, Ext::DEFAULT_PEER_SERVICE_NAME) }
              o.lazy
            end

            option :error_status_codes do |o|
              o.default { env_to_list(Ext::ENV_ERROR_STATUS_CODES, 400...600, comma_separated_only: false) }
              o.lazy
            end

            option :split_by_domain, default: false
          end
        end
      end
    end
  end
end
