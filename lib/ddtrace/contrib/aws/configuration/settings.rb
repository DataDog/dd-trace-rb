require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/aws/ext'

module Datadog
  module Contrib
    module Aws
      module Configuration
        # Custom settings for the AWS integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
