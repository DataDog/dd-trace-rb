require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/ext/http'
require 'ddtrace/contrib/grape/ext'

module Datadog
  module Contrib
    module Grape
      module Configuration
        # Custom settings for the Grape integration
        class Settings < Contrib::Configuration::Settings
          option :enabled, default: true
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
