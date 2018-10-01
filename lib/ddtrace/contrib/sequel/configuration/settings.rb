require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/sequel/ext'

module Datadog
  module Contrib
    module Sequel
      module Configuration
        # Custom settings for the Sequel integration
        class Settings < Contrib::Configuration::Settings
          # Add any custom Sequel settings or behavior here.
        end
      end
    end
  end
end
