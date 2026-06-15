# frozen_string_literal: true

# Shared helpers for OpenTelemetry SDK specs.
module OpenTelemetryHelpers
  # Shut down the metrics and logs providers spawned by
  # OpenTelemetry::SDK.configure so their background threads
  # (PeriodicMetricReader / BatchLogRecordProcessor) don't outlive the
  # example. Each provider only has a #shutdown method on the real SDK
  # class; the Noop default returned when the corresponding SDK gem
  # isn't loaded does not, so guard with defined? + is_a?.
  def shutdown_otel_providers
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
