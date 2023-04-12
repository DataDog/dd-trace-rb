require_relative '../../configuration/settings'
require_relative '../ext'
require_relative '../utils'

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        module Configuration
          # Custom settings for the ActiveRecord integration
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

            option :service_name do |o|
              o.default { Utils.adapter_name }
              o.lazy
            end
          end
        end
      end
    end
  end
end
