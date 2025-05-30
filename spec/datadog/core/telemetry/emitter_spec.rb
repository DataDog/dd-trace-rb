require 'spec_helper'

require 'datadog/core/telemetry/emitter'
require 'datadog/core/telemetry/transport/http'
require 'datadog/core/transport/response'

RSpec.describe Datadog::Core::Telemetry::Emitter do
  subject(:emitter) { described_class.new(transport, logger: logger) }
  let(:logger) { logger_allowing_debug }
  let(:transport) { double(Datadog::Core::Telemetry::Transport::HTTP::Client) }
  let(:response) { double(Datadog::Core::Transport::HTTP::Adapters::Net::Response) }
  let(:response_ok) { true }

  before do
    allow(transport).to receive(:send_telemetry).and_return(response)
    emitter.class.sequence.reset!
  end

  after do
    emitter.class.sequence.reset!
  end

  describe '#initialize' do
    it { is_expected.to be_a_kind_of(described_class) }
    it { expect(emitter.transport).to be(transport) }

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

    context 'when event' do
      context 'is invalid' do
        let(:event) { 'Not an event' }

        it do
          expect_lazy_log(logger, :debug, /Unable to send telemetry request/)
          request
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

        context 'when call is not successful and debug logging is enabled' do
          let(:response) do
            Datadog::Core::Transport::InternalErrorResponse.new(StandardError.new('Failed call'))
          end

          it 'logs the request correctly' do
            expect_lazy_log(logger, :debug, 'Telemetry sent for event')
            request
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
        allow(Datadog::Core::Telemetry::Request).to receive(:build_payload).with(event, 1, debug: false).and_return(payload)

        request

        expect(transport).to have_received(:send_telemetry).with(request_type: request_type, payload: { foo: 'bar' })
      end
    end
  end

  describe 'when initialized multiple times' do
    let(:transport) { double(Datadog::Core::Telemetry::Transport::Telemetry::Transport) }

    context 'sequence is stored' do
      it do
        emitter_first = described_class.new(transport)
        emitter_second = described_class.new(transport)
        expect(emitter_first.class.sequence).to be(emitter_second.class.sequence)
      end
    end
  end
end
