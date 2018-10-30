require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/resque/ext'

module Datadog
  module Contrib
    module Resque
      module Configuration
        # Custom settings for the Resque integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
          option :workers, default: []
        end
      end
    end
  end
end
