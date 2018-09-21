require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/http/ext'

module Datadog
  module Contrib
    module HTTP
      module Configuration
        # Custom settings for the HTTP integration
        class Settings < Contrib::Configuration::Settings
          option :distributed_tracing, default: false
          option :service_name, default: Ext::SERVICE_NAME
          option :tracer, default: Datadog.tracer
        end
      end
    end
  end
end
