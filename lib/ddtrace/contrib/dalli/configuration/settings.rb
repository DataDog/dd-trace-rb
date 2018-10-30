require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/dalli/ext'

module Datadog
  module Contrib
    module Dalli
      module Configuration
        # Custom settings for the Dalli integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
