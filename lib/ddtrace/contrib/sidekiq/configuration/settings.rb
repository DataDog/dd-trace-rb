require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/sidekiq/ext'

module Datadog
  module Contrib
    module Sidekiq
      module Configuration
        # Custom settings for the Sidekiq integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
