require 'spec_helper'

require 'ddtrace/transport/http'

RSpec.describe Datadog::Transport::HTTP do
  describe '#default' do
    subject(:client) { described_class.default(&options_block) }
    let(:options_block) { proc { |t| t.adapter :test } }
    it { is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Client) }

    describe '#deliver' do
      subject(:response) { client.deliver(request) }
      let(:request) { Datadog::Transport::Request.new(:traces, parcel) }
      let(:parcel) { Datadog::Transport::Traces::Parcel.new(get_test_traces(2)) }
      it { expect(response.ok?).to be true }
    end
  end
end
