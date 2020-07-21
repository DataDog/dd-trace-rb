require 'spec_helper'
require 'ddtrace/profiling/spec_helper'

require 'ddtrace'
require 'ddtrace/profiling/transport/http'

RSpec.describe 'Datadog::Profiling::Transport::HTTP integration tests' do
  before do
    skip 'Only runs in fully integrated environment.' unless ENV['TEST_DATADOG_INTEGRATION']
    skip 'Valid API key must be set.' unless ENV['DD_API_KEY'] && !ENV['DD_API_KEY'].empty?
  end

  describe 'HTTP#default' do
    subject(:transport) { Datadog::Profiling::Transport::HTTP.default(options, &option_block) }
    let(:options) { {} }
    let(:option_block) { proc { |_client| } }
    it { is_expected.to be_a(Datadog::Profiling::Transport::HTTP::Client) }

    describe '#send_profiling_flush' do
      subject(:response) { transport.send_profiling_flush(flush) }
      let(:flush) { get_test_profiling_flush }

      shared_examples_for 'a successful profile flush' do
        it do
          is_expected.to be_a(Datadog::Profiling::Transport::HTTP::Response)
          expect([200, 403]).to include(response.code)
        end
      end

      context 'agent' do
        it_behaves_like 'a successful profile flush'
      end

      context 'agentless' do
        let(:options) { { site: 'datadoghq.com', api_key: ENV['DD_API_KEY'] } }
        it_behaves_like 'a successful profile flush'
      end
    end
  end
end
