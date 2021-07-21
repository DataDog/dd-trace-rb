require 'ddtrace/configuration/base'

module Datadog
  module Security
    module Contrib
      module Configuration
        # Common settings for all integrations
        class Settings
          include Datadog::Configuration::Base

          option :enabled, default: true
          option :service_name
        end
      end
    end
  end
end
