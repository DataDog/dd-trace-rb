require 'spec_helper'

require 'ddtrace/transport/http'

RSpec.describe 'Datadog::Transport::HTTP integration tests' do
  before { skip unless ENV['TEST_DATADOG_INTEGRATION'] }

  describe 'for default HTTP client' do
    subject(:client) { Datadog::Transport::HTTP.default }
    it { is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Client) }

    describe '#send_traces' do
      subject(:response) { client.send_traces(traces) }
      let(:traces) { get_test_traces(2) }
      it do
        is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Traces::Response)
        expect(response.ok?).to be true
        expect(response.service_rates).to_not be nil
      end
    end
  end
end
