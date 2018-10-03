require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/rake/ext'

module Datadog
  module Contrib
    module Rake
      module Configuration
        # Custom settings for the Rake integration
        class Settings < Contrib::Configuration::Settings
          option :enabled, default: true
          option :quantize, default: {}
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
