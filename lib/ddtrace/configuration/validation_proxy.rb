require 'forwardable'

module Datadog
  module Configuration
    # Forwards configuration settings that are permitted,
    # but raises errors for access to anything else.
    class ValidationProxy
      extend Forwardable

      def initialize(configuration)
        @configuration = configuration
      end

      protected

      attr_reader :configuration

      # Forwards global configuration settings
      class Global < self
        FORWARDED_METHODS = [
          :api_key,
          :api_key=,
          :diagnostics,
          :env,
          :env=,
          :logger,
          :service,
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
          :configuration,
          *FORWARDED_METHODS
      end

      # Forwards tracing configuration settings
      class Tracing < self
        FORWARDED_METHODS = [
          :analytics,
          :distributed_tracing,
          :log_injection,
          :log_injection=,
          :report_hostname,
          :report_hostname=,
          :runtime_metrics,
          :sampling,
          :test_mode,
          :tracer
        ].freeze

        def_delegators \
          :configuration,
          *FORWARDED_METHODS
      end

      # Forwards profiling configuration settings
      class Profiling < self
        FORWARDED_METHODS = [
          :profiling
        ].freeze

        def_delegators \
          :configuration,
          *FORWARDED_METHODS
      end
    end
  end
end
