require_relative '../../configuration/settings'
require_relative '../ext'

require_relative '../../../../core'

module Datadog
  module Tracing
    module Contrib
      module ActionPack
        module Configuration
          # Custom settings for the ActionPack integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end

            option :analytics_enabled do |o|
              o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, nil) }
              o.lazy
            end

            option :analytics_sample_rate do |o|
              o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
              o.lazy
            end

            # DEV-2.0: Breaking changes for removal.
            option :exception_controller do |o|
              o.on_set do |value|
                if value
                  Datadog::Core.log_deprecation do
                    'The error controller is now automatically detected. '\
                    "Option `#{o.instance_variable_get(:@name)}` is no longer required and will be removed."
                  end
                end
              end
            end

            option :service_name
          end
        end
      end
    end
  end
end
