# frozen_string_literal: true

module OpenTelemetryHelpers
  # OpenTelemetry::SDK.configure overwrites the global meter/logger provider
  # without shutting down the previous one. Background threads
  # (PeriodicMetricReader, BatchLogRecordProcessor) on the abandoned provider
  # keep running. Provider#shutdown is the only documented way to stop them.
  #
  # The is_a? guards exist because when the metrics-sdk / logs-sdk gems aren't
  # loaded, the global is a Noop provider that has no #shutdown.
  #
  # Wrinkle: the OTel spec says Shutdown MUST be called only once per provider
  # instance, but RSpec runs after blocks innermost-first and #shutdown does
  # not reset the global pointer. So when an inner after has already shut down
  # the current global and an outer after runs this helper, #shutdown gets
  # called a second time on the same instance. OTel Ruby tolerates this
  # (MeterProvider#shutdown returns Export::FAILURE, LoggerProvider#shutdown
  # no-ops; neither raises and neither re-touches the already-stopped threads),
  # so the leak fix holds. Not worth tracking last-shutdown state here.
  def self.shutdown_otel_providers
    if defined?(::OpenTelemetry::SDK::Metrics::MeterProvider) &&
        ::OpenTelemetry.meter_provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
      ::OpenTelemetry.meter_provider.shutdown
    end
    if defined?(::OpenTelemetry::SDK::Logs::LoggerProvider) &&
        ::OpenTelemetry.respond_to?(:logger_provider) &&
        ::OpenTelemetry.logger_provider.is_a?(::OpenTelemetry::SDK::Logs::LoggerProvider)
      ::OpenTelemetry.logger_provider.shutdown
    end
  end
end
