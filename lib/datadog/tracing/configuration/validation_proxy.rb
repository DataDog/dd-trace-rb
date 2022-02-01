require 'datadog/core/configuration/validation_proxy'

module Datadog
  module Tracing
    module Configuration
      # Forwards tracing configuration settings
      class ValidationProxy < Core::Configuration::ValidationProxy
        FORWARDED_METHODS = [
          :analytics,
          :distributed_tracing,
          :instrument,
          :instrumented_integrations,
          :log_injection,
          :log_injection=,
          :reduce_log_verbosity,
          :report_hostname,
          :report_hostname=,
          :sampling,
          :test_mode,
          :tracer
        ].freeze

        def_delegators \
          :settings,
          *FORWARDED_METHODS
      end
    end
  end
end
