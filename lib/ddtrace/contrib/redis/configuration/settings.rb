require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/redis/ext'

module Datadog
  module Contrib
    module Redis
      module Configuration
        # Custom settings for the Redis integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
          option :tracer, default: Datadog.tracer
        end
      end
    end
  end
end
