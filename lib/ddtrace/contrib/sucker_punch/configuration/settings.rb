require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module SuckerPunch
      module Configuration
        # Custom settings for the SuckerPunch integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: 'sucker_punch'
        end
      end
    end
  end
end
