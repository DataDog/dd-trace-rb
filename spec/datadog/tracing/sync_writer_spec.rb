require 'spec_helper'

require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/tracing/pipeline'
require 'datadog/tracing/pipeline/span_filter'
require 'datadog/tracing/span'
require 'datadog/tracing/sync_writer'
require 'datadog/tracing/trace_segment'
require 'datadog/tracing/tracer'
require 'ddtrace/transport/http'
require 'ddtrace/transport/http/traces'
require 'ddtrace/transport/traces'

RSpec.describe Datadog::Tracing::SyncWriter do
  subject(:sync_writer) { described_class.new(transport: transport) }

  let(:transport) { Datadog::Transport::HTTP.default { |t| t.adapter :test, buffer } }
  let(:buffer) { [] }

  describe '::new' do
    subject(:sync_writer) { described_class.new(**options) }

    context 'given :agent_settings' do
      let(:options) { { agent_settings: agent_settings } }
      let(:agent_settings) { instance_double(Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings) }
      let(:transport) { instance_double(Datadog::Transport::Traces::Transport) }

      before do
        expect(Datadog::Transport::HTTP)
          .to receive(:default)
          .with(options)
          .and_return(transport)
      end

      it { is_expected.to have_attributes(transport: transport) }
    end
  end

  describe '#write' do
    subject(:write) { sync_writer.write(trace) }

    let(:trace) { get_test_traces(1).first }

    context 'with trace' do
      before { write }

      it { expect(buffer).to have(1).item }
    end

    context 'with filtering' do
      let(:filtered_trace) { Datadog::Tracing::TraceSegment.new([Datadog::Tracing::Span.new('span_1')]) }
      let(:unfiltered_trace) { Datadog::Tracing::TraceSegment.new([Datadog::Tracing::Span.new('span_2')]) }

      before do
        allow(transport).to receive(:send_traces).and_call_original

        Datadog::Tracing::Pipeline.before_flush(
          Datadog::Tracing::Pipeline::SpanFilter.new { |span| span.name == 'span_1' }
        )

        sync_writer.write(unfiltered_trace)
        sync_writer.write(filtered_trace)
      end

      after { Datadog::Tracing::Pipeline.processors = [] }

      it 'only sends the unfiltered traces' do
        expect(transport).to_not have_received(:send_traces)
          .with([filtered_trace])

        expect(transport).to have_received(:send_traces)
          .with([unfiltered_trace])
      end
    end

    it 'publishes after_send event' do
      expect(sync_writer.events.after_send)
        .to receive(:publish)
        .with(sync_writer, match_array(be_a(Datadog::Transport::HTTP::Traces::Response)))
      write
    end
  end

  describe '#stop' do
    subject(:stop) { sync_writer.stop }

    it { is_expected.to eq(true) }
  end

  describe 'integration' do
    context 'when initializing a tracer' do
      subject(:tracer) { Datadog::Tracing::Tracer.new(writer: sync_writer) }

      it { expect(tracer.writer).to be sync_writer }

      context 'then submitting a trace' do
        before do
          tracer.trace('parent.span') do
            tracer.trace('child.span') do
              # Do nothing
            end
          end
        end

        it { expect(buffer).to have(1).item }
      end
    end
  end
end
