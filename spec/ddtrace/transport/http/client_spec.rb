require 'spec_helper'

require 'ddtrace/transport/http'
require 'ddtrace/transport/http/client'

RSpec.describe Datadog::Transport::HTTP::Client do
  subject(:client) { described_class.new(apis, active_api) }

  let(:active_api) { :V2 }
  let(:apis) do
    Datadog::Transport::HTTP::API::Map[
      V2: api_v2,
      V1: api_v1
    ]
  end
  let(:api_v2) { instance_double(Datadog::Transport::HTTP::API::Instance) }
  let(:api_v1) { instance_double(Datadog::Transport::HTTP::API::Instance) }

  describe '#deliver' do
    subject(:response) { client.deliver(request) }
    let(:request) { Datadog::Transport::Request.new(:traces, parcel) }
    let(:parcel) { Datadog::Transport::Traces::Parcel.new(get_test_traces(2)) }

    before do
      expect(api_v2).to receive(:call)
        .with(kind_of(Datadog::Transport::HTTP::Env))
        .and_return(response)
    end

    context 'which returns an OK response' do
    end

    context 'which returns a not found response' do
    end
  end
end
