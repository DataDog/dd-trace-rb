require 'forwardable'

module Datadog
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
          :agent,
          :api_key,
          :api_key=,
          :diagnostics,
          :env,
          :env=,
          :logger,
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

      # Forwards tracing configuration settings
      class Tracing < self
        FORWARDED_METHODS = [
          :agent,
          :analytics,
          :distributed_tracing,
          :instrument,
          :instrumented_integrations,
          :log_injection,
          :log_injection=,
          :reduce_log_verbosity,
          :report_hostname,
          :report_hostname=,
          :runtime_metrics,
          :sampling,
          :test_mode,
          :tracer
        ].freeze

        def_delegators \
          :settings,
          *FORWARDED_METHODS
      end

      # Forwards profiling configuration settings
      class Profiling < self
        FORWARDED_METHODS = [
          :profiling
        ].freeze

        def_delegators \
          :settings,
          *FORWARDED_METHODS
      end

      # Forwards CI configuration settings
      class CI < self
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
