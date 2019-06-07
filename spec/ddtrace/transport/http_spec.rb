require 'spec_helper'

require 'ddtrace/transport/http'

RSpec.describe Datadog::Transport::HTTP do
  describe '#default' do
    subject(:client) { described_class.default(&options_block) }
    let(:options_block) { proc { |t| t.adapter :test, buffer } }
    let(:buffer) { [] }
    it { is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Client) }

    describe '#send_traces' do
      subject(:response) { client.send_traces(traces) }
      let(:traces) { get_test_traces(2) }
      it do
        expect(response.ok?).to be true
        expect(buffer).to have(1).items
      end

      describe 'request' do
        subject(:request) { buffer.first }
        before { response }

        it do
          is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Env)
          expect(request.verb).to eq(:post)
          expect(request.path).to eq('/v0.4/traces')
          expect(request[:headers]['X-Datadog-Trace-Count']).to eq('2')
          expect(request[:headers]['Content-Type']).to eq('application/msgpack')
          expect(request.body).to_not be_empty
        end
      end
    end
  end
end
