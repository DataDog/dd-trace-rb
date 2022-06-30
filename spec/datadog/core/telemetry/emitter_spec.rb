require 'spec_helper'

require 'datadog/core/telemetry/emitter'

RSpec.describe Datadog::Core::Telemetry::Emitter do
  describe '.request' do
    subject(:request) { described_class.request(request_type: request_type) }
    let(:request_type) { 'app-started' }

    before do
      logger = double(Datadog::Core::Logger)
      allow(logger).to receive(:info)
      allow(Datadog).to receive(:logger).and_return(logger)
    end

    context 'when :request_type' do
      context 'is app-started' do
        let(:request_type) { 'app-started' }
        let(:response_ok) { true }
        let(:response) { double(Datadog::Core::Telemetry::Http::Adapters::Net::Response) }

        before do
          http_transport = double(Datadog::Core::Telemetry::Http::Transport)
          allow(Datadog::Core::Telemetry::Http::Transport).to receive(:new).and_return(http_transport)
          allow(response).to receive(:ok?).and_return(response_ok)
          allow(http_transport).to receive(:request).and_return(response)
        end

        after do
          # Clear instance variable to prevent leaking double in the examples
          described_class.remove_instance_variable(:@transporter)
        end

        context 'when call successful' do
          let(:response_ok) { true }

          it do
            is_expected.to eq(response)
            expect(Datadog.logger).to_not have_received(:info)
          end

          it do
            original_seq_id = described_class.seq_id
            described_class.request(request_type: request_type)
            expect(described_class.seq_id).to be(original_seq_id + 1)
          end
        end

        context 'when call unsuccessful' do
          let(:response_ok) { false }

          it do
            original_seq_id = described_class.seq_id
            described_class.request(request_type: request_type)
            expect(described_class.seq_id).to be(original_seq_id)
          end
        end
      end

      context 'is invalid' do
        let(:request_type) { 'app' }

        it 'fails with log message' do
          subject
          expect(Datadog.logger).to have_received(:info) do |message|
            expect(message).to include('Unable to send telemetry request')
          end
        end
      end
    end
  end
end
