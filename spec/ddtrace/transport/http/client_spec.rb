require 'spec_helper'

require 'ddtrace/transport/http/client'
require 'ddtrace/transport/http/service'

RSpec.describe Datadog::Transport::HTTP::Client do
  subject(:client) { described_class.new(service, options) }
  let(:options) { {} }

  describe '#deliver' do
    subject(:response) { client.deliver(parcel) }

    context 'given some traces' do
      let(:parcel) { Datadog::Transport::Traces::Parcel.new(get_test_traces(2)) }

      context 'with an actual service' do
        let(:service) do
          Datadog::Transport::HTTP::Service.new(
            ENV.fetch('DD_AGENT_HOST', 'localhost'),
            ENV.fetch('DD_TRACE_AGENT_PORT', 8126)
          )
        end

        it { expect(response.ok?).to be true }
      end

      context 'with test service' do
        let(:service) { FauxHTTPService.new }
        it { expect(response.ok?).to be true }
      end
    end
  end
end
