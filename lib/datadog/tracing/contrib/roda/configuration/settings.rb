require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Roda
        module Configuration
          # Custom settings for the Roda integration
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end

            option  :analytics_enabled,
                    default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, nil) },
                    lazy: false

            option :analytics_sample_rate,
                   default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                   lazy: false

            option :distributed_tracing, default: true
            option :service_name, default: Ext::SERVICE_NAME
          end
        end
      end
    end
  end
end
