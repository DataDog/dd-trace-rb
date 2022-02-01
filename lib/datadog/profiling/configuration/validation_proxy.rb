require 'datadog/core/configuration/validation_proxy'

module Datadog
  module Profiling
    module Configuration
      # Forwards profiling configuration settings
      class ValidationProxy < Core::Configuration::ValidationProxy
        FORWARDED_METHODS = [
          :profiling
        ].freeze

        def_delegators \
          :settings,
          *FORWARDED_METHODS
      end
    end
  end
end
