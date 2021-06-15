require 'ddtrace/contrib/configuration/settings'
require 'datadog/ci/contrib/cucumber/ext'

module Datadog
  module CI
    module Contrib
      module Cucumber
        module Configuration
          # Custom settings for the Cucumber integration
          class Settings < Datadog::Contrib::Configuration::Settings
            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end

            option :service_name do |o|
              o.default { Datadog.configuration.service_without_fallback || Ext::SERVICE_NAME }
              o.lazy
            end

            option :operation_name do |o|
              o.default { ENV.key?(Ext::ENV_OPERATION_NAME) ? ENV[Ext::ENV_OPERATION_NAME] : Ext::OPERATION_NAME }
              o.lazy
            end
          end
        end
      end
    end
  end
end
