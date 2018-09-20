require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module DelayedJob
      module Configuration
        # Custom settings for the DelayedJob integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: 'delayed_job'.freeze
        end
      end
    end
  end
end
