require_relative '../../../core/configuration/base'

module Datadog
  module AppSec
    module Contrib
      module Configuration
        # Common settings for all integrations
        # TODO: move to datadog/appsec/configuration or remove?
        class Settings
          include Datadog::Core::Configuration::Base

          option :enabled, default: true
          option :service_name
        end
      end
    end
  end
end
