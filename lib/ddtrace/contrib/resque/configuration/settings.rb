require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Resque
      module Configuration
        # Custom settings for the Resque integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: 'resque'
          option :workers, default: []
        end
      end
    end
  end
end
