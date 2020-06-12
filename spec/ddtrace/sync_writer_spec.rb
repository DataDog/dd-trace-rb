require 'spec_helper'

require 'ddtrace'
require 'ddtrace/sync_writer'

RSpec.describe Datadog::SyncWriter do
  subject(:sync_writer) { described_class.new(transport: transport) }
  let(:transport) { Datadog::Transport::HTTP.default { |t| t.adapter :test, buffer } }
  let(:buffer) { [] }

  describe '#write' do
    subject(:write) { sync_writer.write(trace, services) }
    let(:trace) { get_test_traces(1).first }
    let(:services) { nil }

    context 'with trace' do
      before { write }
      it { expect(buffer).to have(1).item }
    end

    context 'with report hostname' do
      let(:hostname) { 'my-host' }

      before(:each) do
        allow(Datadog::Runtime::Socket).to receive(:hostname).and_return(hostname)
      end

      context 'enabled' do
        before { Datadog.configuration.report_hostname = true }
        after { Datadog.configuration.reset! }

        it do
          expect(sync_writer.transport).to receive(:send_traces) do |traces|
            root_span = traces.first.first
            expect(root_span.get_tag(Datadog::Ext::NET::TAG_HOSTNAME)).to eq(hostname)

            # Stub successful request
            200
          end

          write
        end
      end

      context 'disabled' do
        before { Datadog.configuration.report_hostname = false }
        after { Datadog.configuration.reset! }

        it do
          expect(sync_writer.transport).to receive(:send_traces) do |traces|
            root_span = traces.first.first
            expect(root_span.get_tag(Datadog::Ext::NET::TAG_HOSTNAME)).to be nil

            # Stub successful request
            200
          end

          write
        end
      end
    end

    context 'with filtering' do
      let(:filtered_trace) { [Datadog::Span.new(nil, 'span_1')] }
      let(:unfiltered_trace) { [Datadog::Span.new(nil, 'span_2')] }

      before do
        allow(transport).to receive(:send_traces).and_call_original

        Datadog::Pipeline.before_flush(
          Datadog::Pipeline::SpanFilter.new { |span| span.name == 'span_1' }
        )

        sync_writer.write(unfiltered_trace)
        sync_writer.write(filtered_trace)
      end

      after { Datadog::Pipeline.processors = [] }

      it do
        expect(transport).to_not have_received(:send_traces)
          .with([filtered_trace])

        expect(transport).to have_received(:send_traces)
          .with([unfiltered_trace])
      end
    end
  end

  describe '#stop' do
    subject(:stop) { sync_writer.stop }
    it { is_expected.to eq(true) }
  end

  describe 'integration' do
    context 'when initializing a tracer' do
      subject(:tracer) { Datadog::Tracer.new(writer: sync_writer) }
      it { expect(tracer.writer).to be sync_writer }
    end

    context 'when configuring a tracer' do
      subject(:tracer) { Datadog::Tracer.new }
      before { tracer.configure(writer: sync_writer) }
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
