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
        Datadog::Transport::Response.instance_methods.each do |method|
          expect(http_response).to receive(method)
          response.send(method)
        end
      end
    end
  end
end
