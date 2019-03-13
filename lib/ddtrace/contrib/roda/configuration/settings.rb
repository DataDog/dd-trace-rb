require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/roda/ext'

module Datadog
  module Contrib
    module Roda
      module Configuration
        # Custom settings for the Roda integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
