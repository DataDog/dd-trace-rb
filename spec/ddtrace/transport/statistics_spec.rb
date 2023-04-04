require 'spec_helper'

require 'ddtrace'
require 'ddtrace/transport/statistics'

RSpec.describe Datadog::Transport::Statistics do
  context 'when implemented by a class' do
    subject(:object) { stats_class.new }

    let(:stats_class) do
      stub_const('TestObject', Class.new { include Datadog::Transport::Statistics })
    end

    describe '#initialize' do
      it { is_expected.to have_attributes(stats: kind_of(Datadog::Transport::Statistics::Counts)) }
    end

    describe '#update_stats_from_response!' do
      subject(:update) { object.update_stats_from_response!(response) }

      let(:response) { instance_double(Datadog::Transport::Response) }

      before { allow(Datadog.health_metrics).to receive(:send_metrics) }

      context 'when the response' do
        context 'is OK' do
          before do
            allow(response).to receive(:ok?).and_return(true)
            allow(response).to receive(:internal_error?).and_return(false)
          end

          it do
            update
            expect(object.stats.success).to eq(1)
            expect(object.stats.client_error).to eq(0)
            expect(object.stats.server_error).to eq(0)
            expect(object.stats.internal_error).to eq(0)
            expect(object.stats.consecutive_errors).to eq(0)

            expect(Datadog.health_metrics).to have_received(:send_metrics) do |metrics|
              expect(metrics).to be_a_kind_of(Array)
              expect(metrics).to have(1).item
              expect(metrics).to include(kind_of(Datadog::Core::Metrics::Metric))
              expect(metrics.first).to have_attributes(
                type: :api_responses,
                name: nil,
                value: 1
              )
            end
          end
        end

        context 'is a client error' do
          before do
            allow(response).to receive(:ok?).and_return(false)
            allow(response).to receive(:client_error?).and_return(true)
            allow(response).to receive(:server_error?).and_return(false)
            allow(response).to receive(:internal_error?).and_return(false)
          end

          it do
            update
            expect(object.stats.success).to eq(0)
            expect(object.stats.client_error).to eq(1)
            expect(object.stats.server_error).to eq(0)
            expect(object.stats.internal_error).to eq(0)
            expect(object.stats.consecutive_errors).to eq(1)

            expect(Datadog.health_metrics).to have_received(:send_metrics) do |metrics|
              expect(metrics).to be_a_kind_of(Array)
              expect(metrics).to have(1).item
              expect(metrics).to include(kind_of(Datadog::Core::Metrics::Metric))
              expect(metrics.first).to have_attributes(
                type: :api_responses,
                name: nil,
                value: 1
              )
            end
          end
        end

        context 'is a server error' do
          before do
            allow(response).to receive(:ok?).and_return(false)
            allow(response).to receive(:client_error?).and_return(false)
            allow(response).to receive(:server_error?).and_return(true)
            allow(response).to receive(:internal_error?).and_return(false)
          end

          it do
            update
            expect(object.stats.success).to eq(0)
            expect(object.stats.client_error).to eq(0)
            expect(object.stats.server_error).to eq(1)
            expect(object.stats.internal_error).to eq(0)
            expect(object.stats.consecutive_errors).to eq(1)

            expect(Datadog.health_metrics).to have_received(:send_metrics) do |metrics|
              expect(metrics).to be_a_kind_of(Array)
              expect(metrics).to have(1).item
              expect(metrics).to include(kind_of(Datadog::Core::Metrics::Metric))
              expect(metrics.first).to have_attributes(
                type: :api_responses,
                name: nil,
                value: 1
              )
            end
          end
        end

        context 'is an internal error' do
          before do
            allow(response).to receive(:ok?).and_return(false)
            allow(response).to receive(:client_error?).and_return(false)
            allow(response).to receive(:server_error?).and_return(false)
            allow(response).to receive(:internal_error?).and_return(true)
          end

          it do
            update
            expect(object.stats.success).to eq(0)
            expect(object.stats.client_error).to eq(0)
            expect(object.stats.server_error).to eq(0)
            expect(object.stats.internal_error).to eq(1)
            expect(object.stats.consecutive_errors).to eq(1)

            expect(Datadog.health_metrics).to have_received(:send_metrics) do |metrics|
              expect(metrics).to be_a_kind_of(Array)
              expect(metrics).to have(1).item
              expect(metrics).to include(kind_of(Datadog::Core::Metrics::Metric))
              expect(metrics.first).to have_attributes(
                type: :api_errors,
                name: nil,
                value: 1
              )
            end
          end
        end
      end
    end

    describe '#metrics_for_response' do
      subject(:metrics_for_response) { object.metrics_for_response(response) }

      let(:response) { instance_double(Datadog::Transport::Response) }

      context 'when the response' do
        context 'is OK' do
          before do
            allow(response).to receive(:ok?).and_return(true)
            allow(response).to receive(:internal_error?).and_return(false)
          end

          it do
            is_expected.to be_a_kind_of(Hash)
            is_expected.to have(1).item

            expect(metrics_for_response[:api_responses]).to have_attributes(
              type: :api_responses,
              name: nil,
              value: 1
            )
          end
        end

        context 'is a client error' do
          before do
            allow(response).to receive(:ok?).and_return(false)
            allow(response).to receive(:client_error?).and_return(true)
            allow(response).to receive(:server_error?).and_return(false)
            allow(response).to receive(:internal_error?).and_return(false)
          end

          it do
            is_expected.to be_a_kind_of(Hash)
            is_expected.to have(1).item

            expect(metrics_for_response[:api_responses]).to have_attributes(
              type: :api_responses,
              name: nil,
              value: 1
            )
          end
        end

        context 'is a server error' do
          before do
            allow(response).to receive(:ok?).and_return(false)
            allow(response).to receive(:client_error?).and_return(false)
            allow(response).to receive(:server_error?).and_return(true)
            allow(response).to receive(:internal_error?).and_return(false)
          end

          it do
            is_expected.to be_a_kind_of(Hash)
            is_expected.to have(1).item

            expect(metrics_for_response[:api_responses]).to have_attributes(
              type: :api_responses,
              name: nil,
              value: 1
            )
          end
        end

        context 'is an internal error' do
          before do
            allow(response).to receive(:ok?).and_return(false)
            allow(response).to receive(:client_error?).and_return(false)
            allow(response).to receive(:server_error?).and_return(false)
            allow(response).to receive(:internal_error?).and_return(true)
          end

          it do
            is_expected.to be_a_kind_of(Hash)
            is_expected.to have(1).item

            expect(metrics_for_response[:api_errors]).to have_attributes(
              type: :api_errors,
              name: nil,
              value: 1
            )
          end
        end
      end
    end

    describe '#update_stats_from_exception!' do
      subject(:update) { object.update_stats_from_exception!(exception) }

      let(:exception) { instance_double(StandardError) }

      before { allow(Datadog.health_metrics).to receive(:send_metrics) }

      it do
        update
        expect(object.stats.success).to eq(0)
        expect(object.stats.client_error).to eq(0)
        expect(object.stats.server_error).to eq(0)
        expect(object.stats.internal_error).to eq(1)
        expect(object.stats.consecutive_errors).to eq(1)

        expect(Datadog.health_metrics).to have_received(:send_metrics) do |metrics|
          expect(metrics).to be_a_kind_of(Array)
          expect(metrics).to have(1).item
          expect(metrics).to include(kind_of(Datadog::Core::Metrics::Metric))
          expect(metrics.first).to have_attributes(
            type: :api_errors,
            name: nil,
            value: 1
          )
        end
      end
    end

    describe '#metrics_for_exception' do
      subject(:metrics_for_exception) { object.metrics_for_exception(exception) }

      let(:exception) { instance_double(StandardError) }

      it do
        is_expected.to be_a_kind_of(Hash)
        is_expected.to have(1).item

        expect(metrics_for_exception[:api_errors]).to have_attributes(
          type: :api_errors,
          name: nil,
          value: 1
        )
      end
    end
  end
end

RSpec.describe Datadog::Transport::Statistics::Counts do
  subject(:counts) { described_class.new }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        success: 0,
        client_error: 0,
        server_error: 0,
        internal_error: 0,
        consecutive_errors: 0
      )
    end
  end

  describe '#reset!' do
    subject(:reset!) { counts.reset! }

    context 'when the counts have been incremented' do
      before do
        counts.success += 1
        counts.client_error += 1
        counts.server_error += 1
        counts.internal_error += 1
        counts.consecutive_errors += 1
      end

      it 'resets them all to 0' do
        reset!
        expect(counts.success).to eq(0)
        expect(counts.client_error).to eq(0)
        expect(counts.server_error).to eq(0)
        expect(counts.internal_error).to eq(0)
        expect(counts.consecutive_errors).to eq(0)
      end
    end
  end
end
