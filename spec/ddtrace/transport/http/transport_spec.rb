require 'spec_helper'

require 'ddtrace/transport/http/transport'

RSpec.describe Datadog::Transport::HTTP::Transport do
  subject(:transport) { described_class.new(apis, current_api_id) }

  shared_context 'APIs with fallbacks' do
    let(:current_api_id) { :v2 }
    let(:apis) do
      Datadog::Transport::HTTP::API::Map[
        v2: api_v2,
        v1: api_v1
      ].with_fallbacks(v2: :v1)
    end

    let(:api_v1) { instance_double(Datadog::Transport::HTTP::API::Instance, 'v1', encoder: encoder_v1) }
    let(:api_v2) { instance_double(Datadog::Transport::HTTP::API::Instance, 'v2', encoder: encoder_v2) }
    let(:encoder_v1) { instance_double(Datadog::Encoding::Encoder, content_type: 'text/plain') }
    let(:encoder_v2) { instance_double(Datadog::Encoding::Encoder, content_type: 'text/csv') }
  end

  describe '#initialize' do
    include_context 'APIs with fallbacks'

    it { expect(subject.stats).to be_a(Datadog::Transport::Statistics::Counts) }

    it { is_expected.to have_attributes(apis: apis, current_api_id: current_api_id) }
  end

  describe '#send_traces' do
    include_context 'APIs with fallbacks'

    subject(:send_traces) { transport.send_traces(traces) }

    let(:traces) { instance_double(Array) }
    let(:response) { Class.new { include Datadog::Transport::Response }.new }
    let(:responses) { [response] }

    let(:encoded_traces) { double }
    let(:trace_count) { 1 }

    let(:request) { instance_double(Datadog::Transport::Traces::Request) }
    let(:client_v2) { instance_double(Datadog::Transport::HTTP::Client) }
    let(:client_v1) { instance_double(Datadog::Transport::HTTP::Client) }

    before do
      allow(encoder_v2).to receive(:encode_traces).with(traces) do |&block|
        [block.call(encoded_traces, trace_count)]
      end

      allow(encoder_v1).to receive(:encode_traces).with(traces) do |&block|
        [block.call(encoded_traces, trace_count)]
      end

      allow(Datadog::Transport::HTTP::Client).to receive(:new).with(api_v1).and_return(client_v1)
      allow(Datadog::Transport::HTTP::Client).to receive(:new).with(api_v2).and_return(client_v2)
      allow(client_v1).to receive(:send_payload).with(request).and_return(response)
      allow(client_v2).to receive(:send_payload).with(request).and_return(response)

      allow(Datadog::Transport::Traces::Request).to receive(:new).and_return(request)
    end

    context 'which returns an OK response' do
      before { allow(response).to receive(:ok?).and_return(true) }

      it 'sends to only the current API once' do
        is_expected.to eq(responses)
        expect(client_v2).to have_received(:send_payload).with(request).once
      end
    end

    context 'which returns a not found response' do
      before do
        allow(response).to receive(:not_found?).and_return(true)
        allow(response).to receive(:client_error?).and_return(true)
      end

      it 'attempts each API once as it falls back after each failure' do
        is_expected.to eq(responses)

        expect(client_v2).to have_received(:send_payload).with(request).once
        expect(client_v1).to have_received(:send_payload).with(request).once
      end
    end

    context 'which returns an unsupported response' do
      before do
        allow(response).to receive(:unsupported?).and_return(true)
        allow(response).to receive(:client_error?).and_return(true)
      end

      it 'attempts each API once as it falls back after each failure' do
        is_expected.to eq(responses)

        expect(client_v2).to have_received(:send_payload).with(request).once
        expect(client_v1).to have_received(:send_payload).with(request).once
      end
    end
  end

  describe '#downgrade?' do
    include_context 'APIs with fallbacks'

    subject(:downgrade?) { transport.send(:downgrade?, response) }
    let(:response) { instance_double(Datadog::Transport::Response) }

    context 'when there is no fallback' do
      let(:current_api_id) { :v1 }
      it { is_expected.to be false }
    end

    context 'when a fallback is available' do
      let(:current_api_id) { :v2 }

      context 'and the response isn\'t \'not found\' or \'unsupported\'' do
        before do
          allow(response).to receive(:not_found?).and_return(false)
          allow(response).to receive(:unsupported?).and_return(false)
        end

        it { is_expected.to be false }
      end

      context 'and the response is \'not found\'' do
        before do
          allow(response).to receive(:not_found?).and_return(true)
          allow(response).to receive(:unsupported?).and_return(false)
        end

        it { is_expected.to be true }
      end

      context 'and the response is \'unsupported\'' do
        before do
          allow(response).to receive(:not_found?).and_return(false)
          allow(response).to receive(:unsupported?).and_return(true)
        end

        it { is_expected.to be true }
      end
    end
  end

  describe '#current_api' do
    include_context 'APIs with fallbacks'

    subject(:current_api) { transport.current_api }
    it { is_expected.to be(api_v2) }
  end

  describe '#change_api!' do
    include_context 'APIs with fallbacks'

    subject(:change_api!) { transport.send(:change_api!, api_id) }

    context 'when the API ID does not match an API' do
      let(:api_id) { :v99 }
      it { expect { change_api! }.to raise_error(described_class::UnknownApiVersionError) }
    end

    context 'when the API ID matches an API' do
      let(:api_id) { :v1 }
      it { expect { change_api! }.to change { transport.current_api }.from(api_v2).to(api_v1) }
    end
  end

  describe '#downgrade!' do
    include_context 'APIs with fallbacks'

    subject(:downgrade!) { transport.send(:downgrade!) }

    context 'when the API has no fallback' do
      let(:current_api_id) { :v1 }
      it { expect { downgrade! }.to raise_error(described_class::NoDowngradeAvailableError) }
    end

    context 'when the API has fallback' do
      let(:current_api_id) { :v2 }
      it { expect { downgrade! }.to change { transport.current_api }.from(api_v2).to(api_v1) }
    end
  end
end
