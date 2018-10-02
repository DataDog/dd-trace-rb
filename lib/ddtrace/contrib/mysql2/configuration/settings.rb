require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/mysql2/ext'

module Datadog
  module Contrib
    module Mysql2
      module Configuration
        # Custom settings for the Mysql2 integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
