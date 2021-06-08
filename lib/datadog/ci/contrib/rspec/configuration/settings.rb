require 'ddtrace/contrib/configuration/settings'
require 'datadog/ci/contrib/rspec/ext'

module Datadog
  module CI
    module Contrib
      module RSpec
        module Configuration
          # Custom settings for the RSpec integration
          class Settings < Datadog::Contrib::Configuration::Settings
            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end

            option :service_name do |o|
              o.default { Datadog.configuration.service || Ext::SERVICE_NAME }
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
