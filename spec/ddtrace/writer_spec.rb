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
      describe '#initialize' do
        context 'with priority sampling' do
          let(:options) { { priority_sampler: sampler } }
          let(:sampler) { instance_double(Datadog::PrioritySampler) }

          context 'and default transport options' do
            it do
              expect(Datadog::Transport::HTTP).to receive(:default) do |options|
                expect(options).to be_a_kind_of(Hash)
                expect(options[:api_version]).to eq(Datadog::Transport::HTTP::API::V4)
              end

              expect(writer.priority_sampler).to be(sampler)
            end
          end

          context 'and custom transport options' do
            let(:options) { super().merge(transport_options: { api_version: api_version }) }
            let(:api_version) { double('API version') }

            it do
              expect(Datadog::Transport::HTTP).to receive(:default) do |options|
                expect(options).to include(
                  api_version: api_version
                )
              end
              expect(writer.priority_sampler).to be(sampler)
            end
          end
        end
      end

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

        shared_examples_for 'priority sampling update' do
          context 'when a priority sampler' do
            let(:priority_sampler) { instance_double(Datadog::PrioritySampler) }

            context 'is configured' do
              let(:options) { super().merge(priority_sampler: priority_sampler) }

              context 'but service rates are not available' do
                before do
                  allow(response).to receive(:service_rates).and_return(nil)
                  expect(priority_sampler).to_not receive(:update)
                end

                it { expectations.call }
              end

              context 'and service rates are available' do
                let(:service_rates) { instance_double(Hash) }

                before do
                  allow(response).to receive(:service_rates).and_return(service_rates)
                  expect(priority_sampler).to receive(:update)
                    .with(service_rates)
                end

                it { expectations.call }
              end
            end

            context 'is not configured' do
              let(:options) { super().merge(priority_sampler: nil) }
              it { expectations.call }
            end
          end
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

            it_behaves_like 'priority sampling update' do
              let(:expectations) do
                proc do
                  is_expected.to be true
                  expect(writer.stats[:traces_flushed]).to eq(1)
                end
              end
            end

            it_behaves_like 'records environment information'
          end

          context 'a server error' do
            before do
              allow(response).to receive(:ok?).and_return(false)
              allow(response).to receive(:server_error?).and_return(true)
              allow(response).to receive(:internal_error?).and_return(false)
            end

            it_behaves_like 'priority sampling update' do
              let(:expectations) do
                proc do
                  is_expected.to be false
                  expect(writer.stats[:traces_flushed]).to eq(0)
                end
              end
            end

            it_behaves_like 'records environment information'
          end

          context 'an internal error' do
            let(:response) { Datadog::Transport::InternalErrorResponse.new(double('error')) }
            let(:error) { double('error') }

            context 'when a priority sampler' do
              context 'is configured' do
                let(:options) { super().merge(priority_sampler: priority_sampler) }
                let(:priority_sampler) { instance_double(Datadog::PrioritySampler) }
                before { expect(priority_sampler).to_not receive(:update) }

                it do
                  is_expected.to be true
                  expect(writer.stats[:traces_flushed]).to eq(0)
                end
              end

              context 'is not configured' do
                let(:options) { super().merge(priority_sampler: nil) }

                it do
                  is_expected.to be true
                  expect(writer.stats[:traces_flushed]).to eq(0)
                end
              end
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

        context 'when runtime metrics are enabled' do
          before do
            allow_any_instance_of(Datadog::Workers::AsyncTransport)
              .to receive(:start)

            expect_any_instance_of(Datadog::Workers::AsyncTransport)
              .to receive(:enqueue_trace)
              .with(trace)

            allow(Datadog.configuration.runtime_metrics)
              .to receive(:enabled)
              .and_return(true)
          end

          context 'and the trace is not empty' do
            let(:root_span) { instance_double(Datadog::Span) }

            before do
              allow(trace).to receive(:empty?).and_return(false)
              allow(trace).to receive(:first).and_return(root_span)
              allow(Datadog.runtime_metrics).to receive(:associate_with_span)
            end

            it 'associates the root span with runtime_metrics' do
              write

              expect(Datadog.runtime_metrics)
                .to have_received(:associate_with_span)
                .with(root_span)
            end
          end
        end

        context 'when tracer has been stopped' do
          before { writer.stop }

          it 'should not try to record traces' do
            expect_any_instance_of(Datadog::Workers::AsyncTransport).to_not receive(:enqueue_trace)

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
