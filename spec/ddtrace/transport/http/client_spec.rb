require 'spec_helper'

require 'ddtrace/transport/http/client'
require 'ddtrace/transport/http/service'

RSpec.describe Datadog::Transport::HTTP::Client do
  subject(:client) { described_class.new(service, options) }
  let(:service) do
    Datadog::Transport::HTTP::Service.new(
      ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
      ENV.fetch('TEST_DDAGENT_PORT', 8126)
    )
  end
  let(:options) { {} }

  describe '#deliver' do
    subject(:response) { client.deliver(parcel) }

    context 'given some traces' do
      let(:parcel) { Datadog::Transport::Traces::Parcel.new(get_test_traces(2)) }

      it { expect(response.ok?).to be true }
    end
  end
end
