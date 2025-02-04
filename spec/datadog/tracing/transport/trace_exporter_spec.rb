require 'spec_helper'
require 'datadog/tracing/transport/trace_exporter'
require 'datadog/tracing/transport/serializable_trace'
require 'spec/support/tracer_helpers'

RSpec.describe Datadog::Tracing::Transport::TraceExporter::Exporter do
  describe '.new' do
    context 'when created' do
      it 'from config' do
        config = Datadog::Tracing::Transport::TraceExporter::TraceExporterConfig.new
        config.set_url('http://localhost:8126')
        config.set_env('test')
        config.set_service('my-test-service')
        traces = get_test_traces(3, service: 'my-test-service').map do |t|
          Datadog::Tracing::Transport::SerializableTrace.new(t)
        end
        exporter = described_class.new(config)
        exporter.send(traces.to_msgpack, 3)
        expect(exporter).not_to be_nil
      end
    end
  end
end
