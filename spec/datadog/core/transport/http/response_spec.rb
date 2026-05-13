require 'spec_helper'

require 'datadog/core/transport/http/response'

RSpec.describe Datadog::Core::Transport::HTTP::Response do
  context 'when implemented by a class' do
    subject(:response) { response_class.new(http_response) }

    let(:response_class) do
      stub_const('TestResponse', Class.new { include Datadog::Core::Transport::HTTP::Response })
    end
    let(:http_response) { instance_double(Datadog::Core::Transport::Response) }

    describe 'Datadog::Core::Transport::Response methods' do
      it 'are forwarded to the HTTP response' do
        # :inspect is overridden, :json_content_type? is a computed predicate that
        # calls #content_type internally rather than forwarding directly.
        non_forwarded = [:inspect, :json_content_type?]
        (Datadog::Core::Transport::Response.instance_methods - non_forwarded).each do |method|
          expect(http_response).to receive(method)
          response.send(method)
        end
      end
    end

    describe '#code' do
      subject(:code) { response.code }

      let(:http_response) { double('http response') }

      context 'when HTTP response responds to #code' do
        let(:status_code) { double('status code') }

        before { allow(http_response).to receive(:code).and_return(status_code) }

        it 'forwards to the HTTP response' do
          is_expected.to be(status_code)
          expect(http_response).to have_received(:code)
        end
      end

      context 'when HTTP response does not respond to #code' do
        it { is_expected.to be nil }
      end
    end

    describe '#content_type' do
      subject(:content_type) { response.content_type }

      let(:http_response) { double('http response') }

      context 'when HTTP response responds to #content_type' do
        before { allow(http_response).to receive(:content_type).and_return('application/json') }

        it 'forwards to the HTTP response' do
          is_expected.to eq('application/json')
        end
      end

      context 'when HTTP response does not respond to #content_type' do
        it { is_expected.to be nil }
      end
    end

    describe '#json_content_type?' do
      subject(:json_content_type?) { response.json_content_type? }

      let(:http_response) { double('http response', content_type: header_value) }

      context 'when Content-Type is "application/json"' do
        let(:header_value) { 'application/json' }

        it { is_expected.to be true }
      end

      context 'when Content-Type is "application/json" with a different case' do
        let(:header_value) { 'Application/JSON' }

        it { is_expected.to be true }
      end

      context 'when Content-Type is a "+json" media type' do
        let(:header_value) { 'application/vnd.api+json' }

        it { is_expected.to be true }
      end

      context 'when Content-Type has a charset parameter' do
        let(:header_value) { 'application/json; charset=utf-8' }

        it { is_expected.to be true }
      end

      context 'when Content-Type has a charset parameter without surrounding space' do
        let(:header_value) { 'application/json;charset=utf-8' }

        it { is_expected.to be true }
      end

      context 'when Content-Type is "+json" with a parameter' do
        let(:header_value) { 'application/vnd.api+json; charset=utf-8' }

        it { is_expected.to be true }
      end

      context 'when Content-Type is text/plain' do
        let(:header_value) { 'text/plain' }

        it { is_expected.to be false }
      end

      context 'when Content-Type is missing' do
        let(:header_value) { nil }

        it { is_expected.to be false }
      end
    end
  end
end

RSpec.describe Datadog::Core::Transport::HTTP::NotJsonResponseError do
  subject(:error) { described_class.new(http_response) }

  let(:http_response) do
    double(
      'http response',
      content_type: 'text/html',
      code: 500,
      payload: payload,
    )
  end

  context 'with a short payload' do
    let(:payload) { '<html>oops</html>' }

    it 'includes the content type, status code, and payload in the message' do
      expect(error.message).to include('Content-Type: "text/html"')
      expect(error.message).to include('status: 500')
      expect(error.message).to include('payload: "<html>oops</html>"')
    end
  end

  context 'with a long payload' do
    let(:payload) { 'a' * 2000 }

    it 'truncates the payload in the message' do
      expect(error.message).to include('... (truncated)')
      expect(error.message.length).to be < payload.length + 200
    end
  end

  context 'with a nil payload' do
    let(:payload) { nil }

    it 'does not raise when formatting' do
      expect { error.message }.not_to raise_error
    end
  end
end
