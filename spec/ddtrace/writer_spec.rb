require 'spec_helper'

require 'ddtrace'
require 'json'

RSpec.describe Datadog::Writer do
  include HttpHelpers

  describe 'instance' do
    subject(:writer) { described_class.new(options) }

    let(:options) { { transport: transport } }
    let(:transport) { instance_double(Datadog::Transport::Traces::Transport) }

    describe 'behavior' do
      describe '#send_spans' do
        subject(:send_spans) { writer.send_spans(traces, writer.transport) }

        let(:traces) { get_test_traces(1) }
        let(:transport_stats) { instance_double(Datadog::Transport::Statistics) }
        let(:responses) { [response] }

        before do
          allow(transport).to receive(:send_traces)
            .with(traces)
            .and_return(responses)

          allow(transport).to receive(:stats).and_return(transport_stats)

          allow(Datadog::Diagnostics::EnvironmentLogger).to receive(:log!)
        end

        shared_examples 'records environment information' do
          it 'calls environment logger' do
            subject
            expect(Datadog::Diagnostics::EnvironmentLogger).to have_received(:log!).with(responses)
          end
        end

        context 'which returns a response that is' do
          let(:response) { instance_double(Datadog::Transport::HTTP::Traces::Response, trace_count: 1) }

          context 'successful' do
            before do
              allow(response).to receive(:ok?).and_return(true)
              allow(response).to receive(:server_error?).and_return(false)
              allow(response).to receive(:internal_error?).and_return(false)
            end

            it do
              is_expected.to be true
              expect(writer.stats[:traces_flushed]).to eq(1)
            end

            it_behaves_like 'records environment information'
          end

          context 'a server error' do
            before do
              allow(response).to receive(:ok?).and_return(false)
              allow(response).to receive(:server_error?).and_return(true)
              allow(response).to receive(:internal_error?).and_return(false)
            end

            it do
              is_expected.to be false
              expect(writer.stats[:traces_flushed]).to eq(0)
            end

            it_behaves_like 'records environment information'
          end

          context 'an internal error' do
            let(:response) { Datadog::Transport::InternalErrorResponse.new(double('error')) }
            let(:error) { double('error') }

            it do
              is_expected.to be true
              expect(writer.stats[:traces_flushed]).to eq(0)
            end

            it_behaves_like 'records environment information'
          end
        end

        context 'with multiple responses' do
          let(:response1) do
            instance_double(Datadog::Transport::HTTP::Traces::Response,
                            internal_error?: false,
                            server_error?: false,
                            ok?: true,
                            trace_count: 10)
          end
          let(:response2) do
            instance_double(Datadog::Transport::HTTP::Traces::Response,
                            internal_error?: false,
                            server_error?: false,
                            ok?: true,
                            trace_count: 20)
          end

          let(:responses) { [response1, response2] }

          context 'and at least one being server error' do
            let(:response2) do
              instance_double(Datadog::Transport::HTTP::Traces::Response,
                              internal_error?: false,
                              server_error?: true,
                              ok?: false)
            end

            it do
              is_expected.to be_falsey
              expect(writer.stats[:traces_flushed]).to eq(10)
            end
          end

          it_behaves_like 'records environment information'
        end

        context 'with report hostname' do
          let(:hostname) { 'my-host' }
          let(:response) { instance_double(Datadog::Transport::HTTP::Traces::Response, trace_count: 1) }

          before do
            allow(Datadog::Runtime::Socket).to receive(:hostname).and_return(hostname)
            allow(response).to receive(:ok?).and_return(true)
            allow(response).to receive(:server_error?).and_return(false)
            allow(response).to receive(:internal_error?).and_return(false)
          end

          context 'enabled' do
            before { Datadog.configuration.report_hostname = true }

            after { Datadog.configuration.reset! }

            it do
              expect(transport).to receive(:send_traces) do |traces|
                root_span = traces.first.first
                expect(root_span.get_tag(Datadog::Ext::NET::TAG_HOSTNAME)).to eq(hostname)
                [response]
              end

              send_spans
            end
          end

          context 'disabled' do
            before { Datadog.configuration.report_hostname = false }

            after { Datadog.configuration.reset! }

            it do
              expect(writer.transport).to receive(:send_traces) do |traces|
                root_span = traces.first.first
                expect(root_span.get_tag(Datadog::Ext::NET::TAG_HOSTNAME)).to be nil
                [response]
              end

              send_spans
            end
          end
        end
      end

      describe '#write' do
        subject(:write) { writer.write(trace, services) }

        let(:trace) { instance_double(Array) }
        let(:services) { nil }

        context 'when tracer has been stopped' do
          before { writer.stop }

          it 'does not try to record traces' do
            expect_any_instance_of(Datadog::Workers::AsyncTransport).to_not receive(:enqueue_trace)

            # Ensure clean output, as failing to start the
            # worker in this situation is not an error.
            expect(Datadog.logger).to_not receive(:debug)

            write
          end
        end
      end

      describe '#flush_completed' do
        subject(:flush_completed) { writer.flush_completed }
        it { is_expected.to be_a_kind_of(described_class::FlushCompleted) }
      end

      describe described_class::FlushCompleted do
        subject(:event) { described_class.new }

        describe '#name' do
          subject(:name) { event.name }
          it { is_expected.to be :flush_completed }
        end
      end
    end
  end
end
