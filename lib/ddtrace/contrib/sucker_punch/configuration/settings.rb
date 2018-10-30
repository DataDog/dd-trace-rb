require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/sucker_punch/ext'

module Datadog
  module Contrib
    module SuckerPunch
      module Configuration
        # Custom settings for the SuckerPunch integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
