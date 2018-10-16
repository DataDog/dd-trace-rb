require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/excon/ext'

module Datadog
  module Contrib
    module Excon
      module Configuration
        # Custom settings for the Excon integration
        class Settings < Contrib::Configuration::Settings
          option :distributed_tracing, default: false
          option :error_handler, default: nil
          option :service_name, default: Ext::SERVICE_NAME
          option :split_by_domain, default: false
        end
      end
    end
  end
end
