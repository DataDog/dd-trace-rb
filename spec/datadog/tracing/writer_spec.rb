require 'spec_helper'

require 'json'

require 'datadog/core'
require 'datadog/core/diagnostics/environment_logger'
require 'datadog/tracing/runtime/metrics'
require 'datadog/tracing/trace_segment'
require 'datadog/tracing/writer'
require 'datadog/tracing/workers'
require 'datadog/tracing/transport/http'
require 'datadog/tracing/transport/http/traces'
require 'datadog/core/transport/response'
require 'datadog/tracing/transport/statistics'
require 'datadog/tracing/transport/traces'

RSpec.describe Datadog::Tracing::Writer do
  include HttpHelpers

  describe 'instance' do
    subject(:writer) { described_class.new(options) }

    let(:options) { { transport: transport } }
    let(:transport) { instance_double(Datadog::Tracing::Transport::Traces::Transport) }

    describe 'behavior' do
      describe '#initialize' do
        let(:options) { {} }

        context 'and default transport options' do
          it do
            expect(Datadog::Tracing::Transport::HTTP).to receive(:default) do |**options|
              expect(options).to be_empty
            end

            writer
          end
        end

        context 'and custom transport options' do
          let(:options) { super().merge(transport_options: { api_version: api_version }) }
          let(:api_version) { double('API version') }

          it do
            expect(Datadog::Tracing::Transport::HTTP).to receive(:default) do |**options|
              expect(options).to include(api_version: api_version)
            end

            writer
          end
        end

        context 'with agent_settings' do
          let(:agent_settings) { double('AgentSettings') }

          let(:options) { { agent_settings: agent_settings } }

          it 'configures the transport using the agent_settings' do
            expect(Datadog::Tracing::Transport::HTTP).to receive(:default).with(agent_settings: agent_settings)

            writer
          end
        end
      end

      describe '#start_worker' do
        let(:worker) { double(:async_transport, start: nil) }
        let(:async_transport_params) do
          {
            transport: transport,
            buffer_size: Datadog::Tracing::Workers::AsyncTransport::DEFAULT_BUFFER_MAX_SIZE,
            on_trace: anything,
            interval: Datadog::Tracing::Workers::AsyncTransport::DEFAULT_FLUSH_INTERVAL,
            shutdown_timeout: Datadog::Tracing::Workers::AsyncTransport::DEFAULT_SHUTDOWN_TIMEOUT
          }
        end

        before do
          expect(Datadog::Tracing::Workers::AsyncTransport).to(
            receive(:new).with(**expected_async_transport_params).and_return(worker)
          )
        end

        context 'without shutdown timeout' do
          let(:expected_async_transport_params) { async_transport_params }

          it 'creates worker with default shutdown timeout' do
            writer.start
          end
        end

        context 'with shutdown timeout provided in options' do
          let(:options) { { transport: transport, shutdown_timeout: 1000 } }
          let(:expected_async_transport_params) { async_transport_params.merge(shutdown_timeout: 1000) }

          it 'creates worker with configured shutdown timeout' do
            writer.start
          end
        end
      end

      describe '#send_spans' do
        subject(:send_spans) { writer.send_spans(traces, writer.transport) }

        let(:traces) { get_test_traces(1) }
        let(:transport_stats) { instance_double(Datadog::Tracing::Transport::Statistics) }
        let(:responses) { [response] }
        let(:response) { double('response') }

        before do
          allow(transport).to receive(:send_traces)
            .with(traces)
            .and_return(responses)

          allow(transport).to receive(:stats).and_return(transport_stats)

          allow(Datadog::Tracing::Diagnostics::EnvironmentLogger).to receive(:collect_and_log!)
        end

        shared_examples 'after_send events' do
          it 'publishes after_send event' do
            writer.events.after_send.subscribe do |writer, responses|
              expect(writer).to be(self.writer)
              expect(responses).to be(self.responses)
            end

            send_spans
          end
        end

        context 'which returns a response that is' do
          let(:response) { instance_double(Datadog::Tracing::Transport::HTTP::Traces::Response, trace_count: 1) }

          context 'successful' do
            before do
              allow(response).to receive(:ok?).and_return(true)
              allow(response).to receive(:server_error?).and_return(false)
              allow(response).to receive(:internal_error?).and_return(false)
            end

            it_behaves_like 'after_send events'
          end

          context 'a server error' do
            before do
              allow(response).to receive(:ok?).and_return(false)
              allow(response).to receive(:server_error?).and_return(true)
              allow(response).to receive(:internal_error?).and_return(false)
            end

            it_behaves_like 'after_send events'
          end

          context 'an internal error' do
            let(:response) { Datadog::Core::Transport::InternalErrorResponse.new(double('error')) }
            let(:error) { double('error') }

            it_behaves_like 'after_send events'
          end
        end

        context 'with multiple responses' do
          let(:response1) do
            instance_double(
              Datadog::Tracing::Transport::HTTP::Traces::Response,
              internal_error?: false,
              server_error?: false,
              ok?: true,
              trace_count: 10
            )
          end
          let(:response2) do
            instance_double(
              Datadog::Tracing::Transport::HTTP::Traces::Response,
              internal_error?: false,
              server_error?: false,
              ok?: true,
              trace_count: 20
            )
          end

          let(:responses) { [response1, response2] }

          context 'and at least one being server error' do
            let(:response2) do
              instance_double(
                Datadog::Tracing::Transport::HTTP::Traces::Response,
                internal_error?: false,
                server_error?: true,
                ok?: false
              )
            end

            it do
              is_expected.to be_falsey
              expect(writer.stats[:traces_flushed]).to eq(10)
            end
          end

          it_behaves_like 'after_send events'
        end
      end

      describe '#write' do
        subject(:write) { writer.write(trace) }

        let(:trace) { instance_double(Datadog::Tracing::TraceSegment, service: service, empty?: empty?) }
        let(:service) { 'my-service' }
        let(:empty?) { true }

        before do
          allow(Datadog.configuration.runtime_metrics)
            .to receive(:enabled).and_return(false)
        end

        context 'when runtime metrics are enabled' do
          before do
            allow_any_instance_of(Datadog::Tracing::Workers::AsyncTransport)
              .to receive(:start)

            expect_any_instance_of(Datadog::Tracing::Workers::AsyncTransport)
              .to receive(:enqueue_trace)
              .with(trace)

            allow(Datadog.configuration.runtime_metrics)
              .to receive(:enabled)
              .and_return(true)
          end

          context 'and the trace is not empty' do
            let(:empty?) { false }

            before do
              allow(trace).to receive(:empty?).and_return(false)
              allow(Datadog::Tracing::Runtime::Metrics).to receive(:associate_trace)
            end

            it 'associates the root span with runtime_metrics' do
              write

              expect(Datadog::Tracing::Runtime::Metrics)
                .to have_received(:associate_trace)
                .with(trace)
            end
          end
        end

        context 'when tracer has been stopped' do
          before { writer.stop }

          it 'does not try to record traces' do
            expect_any_instance_of(Datadog::Tracing::Workers::AsyncTransport).to_not receive(:enqueue_trace)

            # Ensure clean output, as failing to start the
            # worker in this situation is not an error.
            expect(Datadog.logger).to_not receive(:debug)

            write
          end
        end
      end
    end
  end
end
