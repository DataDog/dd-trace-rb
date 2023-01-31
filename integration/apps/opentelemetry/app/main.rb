require_relative 'datadog'

otel_tracer = OpenTelemetry.tracer_provider.tracer('otel-tracer')

# OTel -> Otel
otel_tracer.in_span('otel-parent') do
  otel_tracer.in_span('otel-child') {}
end

# Datadog -> Otel
Datadog::Tracing.trace('datadog-parent') do
  otel_tracer.in_span('otel-child') {}
end

# Otel -> Datadog
otel_tracer.in_span('otel-parent') do
  Datadog::Tracing.trace('datadog-child') {}
end