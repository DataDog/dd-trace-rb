require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module GC
      module Configuration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: 'gc'
        end
      end
    end
  end
end
