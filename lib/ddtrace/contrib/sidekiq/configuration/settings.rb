require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Sidekiq
      module Configuration
        # Custom settings for the Sidekiq integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: 'sidekiq'
        end
      end
    end
  end
end
