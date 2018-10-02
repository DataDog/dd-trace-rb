require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/grpc/ext'

module Datadog
  module Contrib
    module GRPC
      module Configuration
        # Custom settings for the gRPC integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
          option :tracer, default: Datadog.tracer
        end
      end
    end
  end
end
