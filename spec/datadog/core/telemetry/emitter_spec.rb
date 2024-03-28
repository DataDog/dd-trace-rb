require 'spec_helper'

require 'datadog/core/telemetry/emitter'

RSpec.describe Datadog::Core::Telemetry::Emitter do
  subject(:emitter) { described_class.new(http_transport: http_transport) }
  let(:http_transport) { double(Datadog::Core::Telemetry::Http::Transport) }
  let(:response) { double(Datadog::Core::Telemetry::Http::Adapters::Net::Response) }
  let(:response_ok) { true }

  before do
    allow(http_transport).to receive(:request).and_return(response)
    emitter.class.sequence.reset!
  end

  after do
    emitter.class.sequence.reset!
  end

  describe '#initialize' do
    context 'when no params provided' do
      subject(:emitter) { described_class.new }
      it { is_expected.to be_a_kind_of(described_class) }
    end

    context 'when :http_transport is provided' do
      let(:http_transport) { double(Datadog::Core::Telemetry::Http::Transport) }
      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(emitter.http_transport).to be(http_transport) }
    end

    it 'seq_id begins with 1' do
      original_seq_id = emitter.class.sequence.instance_variable_get(:@current)
      expect(original_seq_id).to be(1)
    end
  end

  describe '#request' do
    subject(:request) { emitter.request(event) }
    let(:event) { double('event', type: request_type, payload: payload) }
    let(:request_type) { double('request_type') }
    let(:payload) { { foo: 'bar' } }

    before do
      logger = double(Datadog::Core::Logger)
      allow(logger).to receive(:debug)
      allow(Datadog).to receive(:logger).and_return(logger)
    end

    context 'when event' do
      context 'is invalid' do
        let(:event) { 'Not an event' }

        it do
          request

          expect(Datadog.logger).to have_received(:debug) do |message|
            expect(message).to include('Unable to send telemetry request')
          end
        end
      end

      context 'is app-started' do
        let(:request_type) { 'app-started' }

        context 'when call is successful' do
          let(:response_ok) { true }

          it { is_expected.to eq(response) }

          it 'seq_id is incremented' do
            original_seq_id = emitter.class.sequence.instance_variable_get(:@current)
            request
            expect(emitter.class.sequence.instance_variable_get(:@current)).to be(original_seq_id + 1)
          end
        end
      end
    end

    context 'with data' do
      subject(:request) { emitter.request(event) }
      let(:event) { double('event', type: request_type) }
      let(:request_type) { double('request_type') }

      let(:payload) { { foo: 'bar' } }

      it 'creates a telemetry event with data' do
        allow(Datadog::Core::Telemetry::Request).to receive(:build_payload).with(event, 1).and_return(payload)

        request

        expect(http_transport).to have_received(:request).with(request_type: request_type, payload: '{"foo":"bar"}')
      end
    end
  end

  describe 'when initialized multiple times' do
    let(:http_transport) { double(Datadog::Core::Telemetry::Http::Transport) }

    context 'sequence is stored' do
      it do
        emitter_first = described_class.new(http_transport: http_transport)
        emitter_second = described_class.new(http_transport: http_transport)
        expect(emitter_first.class.sequence).to be(emitter_second.class.sequence)
      end
    end
  end
end
