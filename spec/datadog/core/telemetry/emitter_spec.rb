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
    subject(:request) { emitter.request(request_type) }
    let(:request_type) { :'app-started' }

    before do
      logger = double(Datadog::Core::Logger)
      allow(logger).to receive(:debug)
      allow(Datadog).to receive(:logger).and_return(logger)
    end

    context 'when :request_type' do
      context 'is invalid' do
        let(:request_type) { 'app' }
        it do
          request
          expect(Datadog.logger).to have_received(:debug) do |message|
            expect(message).to include('Unable to send telemetry request')
          end
        end
      end

      context 'is app-started' do
        let(:request_type) { :'app-started' }

        context 'when call is successful' do
          let(:response_ok) { true }

          it 'no logs are produced' do
            is_expected.to eq(response)
            expect(Datadog.logger).to_not have_received(:debug)
          end

          it 'seq_id is incremented' do
            original_seq_id = emitter.class.sequence.instance_variable_get(:@current)
            request
            expect(emitter.class.sequence.instance_variable_get(:@current)).to be(original_seq_id + 1)
          end
        end
      end
    end

    context 'with data' do
      subject(:request) { emitter.request(request_type, data: data) }
      let(:data) { { changes: ['test-data'] } }
      let(:request_type) { 'app-client-configuration-change' }
      let(:event) { double('event') }

      it 'creates a telemetry event with data' do
        expect(Datadog::Core::Telemetry::Event).to receive(:new).and_return(event)
        expect(event).to receive(:telemetry_request).with(
          request_type: request_type,
          seq_id: be_a(Integer),
          data: data,
          payload: nil
        )
        request
      end
    end

    context 'with data and payload' do
      subject(:request) { emitter.request(:'app-started', data: {}, payload: {}) }

      it 'fails to send request' do
        request
        expect(Datadog.logger).to have_received(:debug) do |message|
          expect(message).to include('Can not provide data and payload')
        end
      end
    end

    context 'metrics' do
      let(:request_type) { 'generate-metrics' }
      let(:event) { double('event') }
      let(:payload) { {} }
      subject(:request) { emitter.request(request_type, payload: payload) }

      it 'creates a telemetry metric with payload' do
        expect(Datadog::Core::Telemetry::Event).to receive(:new).and_return(event)
        expect(event).to receive(:telemetry_request).with(
          request_type: request_type,
          seq_id: be_a(Integer),
          data: nil,
          payload: payload
        )
        request
      end

      context 'missing payload' do
        let(:payload) { nil }

        it 'fail to send metric evenet' do
          request
          expect(Datadog.logger).to have_received(:debug) do |message|
            expect(message).to include('Unable to send telemetry request')
          end
        end
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
