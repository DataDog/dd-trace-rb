# frozen_string_literal: true

module OpenTelemetryHelpers
  # Guards exist because the Noop providers returned when the metrics-sdk /
  # logs-sdk gems aren't loaded don't have #shutdown.
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
