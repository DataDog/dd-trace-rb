# typed: false

require 'spec_helper'
require 'datadog/opentelemetry'

RSpec.describe Datadog::OpenTelemetry do
  context 'with Datadog TraceProvider' do
    around do |example|
      original = OpenTelemetry.tracer_provider
      OpenTelemetry.tracer_provider = Datadog::OpenTelemetry::Trace::TracerProvider.new

      example.run
    ensure
      OpenTelemetry.tracer_provider = original
    end

    let(:tracer) { OpenTelemetry.tracer_provider.tracer('test_tracer') }

    it 'returns same tracer on successive invocations' do
      expect(tracer).to be(OpenTelemetry.tracer_provider.tracer('test_tracer'))
    end
  end
end
