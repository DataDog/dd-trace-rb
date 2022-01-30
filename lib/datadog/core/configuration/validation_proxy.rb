require 'forwardable'

module Datadog
  module Core
    module Configuration
      # Forwards configuration settings that are permitted,
      # but raises errors for access to anything else.
      class ValidationProxy
        extend Forwardable

        FORWARDED_METHODS = [
          :reset!
        ].freeze

        def_delegators \
          :settings,
          *FORWARDED_METHODS

        def initialize(settings)
          @settings = settings
        end

        protected

        attr_reader :settings

        # Forwards global configuration settings
        class Global < self
          FORWARDED_METHODS = [
            :api_key,
            :api_key=,
            :diagnostics,
            :env,
            :env=,
            :logger,
            :runtime_metrics,
            :service,
            :service_without_fallback,
            :service=,
            :site,
            :site=,
            :tags,
            :tags=,
            :time_now_provider,
            :time_now_provider=,
            :version,
            :version=
          ].freeze

          def_delegators \
            :settings,
            *FORWARDED_METHODS
        end
      end
    end
  end
end
