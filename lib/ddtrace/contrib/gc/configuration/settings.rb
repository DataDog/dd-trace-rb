require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/gc/ext'

module Datadog
  module Contrib
    module GC
      module Configuration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
