require 'spec_helper'

require 'datadog/core/telemetry/emitter'

RSpec.describe Datadog::Core::Telemetry::Emitter do
  describe '.request' do
    subject(:request) { described_class.request(request_type: request_type) }
    let(:request_type) { 'app-started' }

    context 'when :request_type' do
      context 'is app-started' do
        let(:request_type) { 'app-started' }

        # it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::TelemetryRequest) }
        # it { expect(request.request_type).to eql(request_type) }
      end

      context 'is invalid' do
        let(:request_type) { 'app' }

        it 'fails with log message' do
          expect(Datadog.logger).to have_received(:info) do |message|
            expect(message).to include('Unable to send telemetry request')
          end
        end
      end
    end

    # context 'when called twice' do
    #   context 'seq_id is incremented' do
    #     it do
    #       request_first = described_class.request(request_type: request_type)
    #       request_second = described_class.request(request_type: request_type)
    #       expect(request_second.seq_id).to eql(request_first.seq_id + 1)
    #     end
    #   end

    #   context 'with invalid parameters' do
    #     context 'seq_id is not incremented' do
    #       it do
    #         request_first = described_class.request(request_type: request_type)
    #         expect { described_class.request(request_type: 'test') }.to raise_error(ArgumentError)
    #         request_third = described_class.request(request_type: request_type)
    #         expect(request_third.seq_id).to eql(request_first.seq_id + 1)
    #       end
    #     end
    #   end
    # end
  end
end
