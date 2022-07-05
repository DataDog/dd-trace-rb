require 'spec_helper'

require 'datadog/core/telemetry/emitter'

RSpec.describe Datadog::Core::Telemetry::Emitter do
  subject(:emitter) { described_class.new(sequence: sequence, http_transport: http_transport) }
  let(:sequence) { Datadog::Core::Utils::Sequence.new(1) }
  let(:http_transport) { double(Datadog::Core::Telemetry::Http::Transport) }
  let(:response) { double(Datadog::Core::Telemetry::Http::Adapters::Net::Response) }
  let(:response_ok) { true }

  before do
    allow(http_transport).to receive(:request).and_return(response)
    allow(response).to receive(:ok?).and_return(response_ok)
  end

  describe '#initialize' do
    context 'when no params provided' do
      subject(:emitter) { described_class.new }
      it { is_expected.to be_a_kind_of(described_class) }
    end

    context 'when :sequence is provided' do
      let(:sequence) { Datadog::Core::Utils::Sequence.new(1) }
      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(emitter.sequence).to be(sequence) }
    end

    context 'when :http_transport is provided' do
      let(:http_transport) { double(Datadog::Core::Telemetry::Http::Transport) }
      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(emitter.http_transport).to be(http_transport) }
    end

    it 'seq_id begins with 1' do
      original_seq_id = emitter.sequence.instance_variable_get(:@current)
      expect(original_seq_id).to be(1)
    end
  end

  describe '#request' do
    subject(:request) { emitter.request(request_type) }
    let(:request_type) { 'app-started' }

    before do
      logger = double(Datadog::Core::Logger)
      allow(logger).to receive(:info)
      allow(Datadog).to receive(:logger).and_return(logger)
    end

    context 'when :request_type' do
      context 'is invalid' do
        let(:request_type) { 'app' }
        it do
          request
          expect(Datadog.logger).to have_received(:info) do |message|
            expect(message).to include('Unable to send telemetry request')
          end
        end
      end

      context 'is app-started' do
        let(:request_type) { 'app-started' }

        context 'when call is successful' do
          let(:response_ok) { true }

          it 'no logs are produced' do
            is_expected.to eq(response)
            expect(Datadog.logger).to_not have_received(:info)
          end

          it 'seq_id is incremented' do
            original_seq_id = emitter.sequence.instance_variable_get(:@current)
            request
            expect(emitter.sequence.instance_variable_get(:@current)).to be(original_seq_id + 1)
          end
        end
      end
    end
  end
end
