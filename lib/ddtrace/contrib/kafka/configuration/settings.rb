require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/kafka/ext'

module Datadog
  module Contrib
    module Kafka
      module Configuration
        # Custom settings for the Kafka integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
