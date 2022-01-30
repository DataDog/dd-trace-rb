require 'datadog/core/configuration/validation_proxy'

module Datadog
  module CI
    module Configuration
      # Forwards CI configuration settings
      class ValidationProxy < Core::Configuration::ValidationProxy
        FORWARDED_METHODS = [
          :ci_mode
        ].freeze

        def_delegators \
          :settings,
          *FORWARDED_METHODS
      end
    end
  end
end
