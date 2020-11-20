require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/pg/ext'

module Datadog
  module Contrib
    module Pg
      module Configuration
        # Custom settings for the PG integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
