require 'spec_helper'

require 'ddtrace/transport/http/response'

RSpec.describe Datadog::Transport::HTTP::Response do
  context 'when implemented by a class' do
    subject(:response) { response_class.new(http_response) }

    let(:response_class) do
      stub_const('TestResponse', Class.new { include Datadog::Transport::HTTP::Response })
    end
    let(:http_response) { instance_double(Datadog::Transport::Response) }

    describe 'Datadog::Transport::Response methods' do
      it 'are forwarded to the HTTP response' do
        (Datadog::Transport::Response.instance_methods - [:inspect]).each do |method|
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
  end
end
