require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/delayed_job/ext'

module Datadog
  module Contrib
    module DelayedJob
      module Configuration
        # Custom settings for the DelayedJob integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
