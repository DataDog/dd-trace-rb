require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Shoryuken
      module Configuration
        # Default settings for the Shoryuken integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
