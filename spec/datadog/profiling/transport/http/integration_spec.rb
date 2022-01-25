# typed: ignore
require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'ddtrace'
require 'datadog/profiling/transport/http'

RSpec.describe 'Datadog::Profiling::Transport::HTTP integration tests' do
  before do
    skip 'Profiling is not supported on JRuby' if PlatformHelpers.jruby?
    skip 'Profiling is not supported on TruffleRuby' if PlatformHelpers.truffleruby?
  end

  describe 'HTTP#default' do
    subject(:transport) do
      Datadog::Profiling::Transport::HTTP.default(
        profiling_upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
        **options
      )
    end

    before do
      # Make sure the transport is being built correctly, even if we then skip the tests
      transport
    end

    let(:settings) { Datadog::Core::Configuration::Settings.new }

    describe '#send_profiling_flush' do
      subject(:response) { transport.send_profiling_flush(flush) }

      let(:flush) { get_test_profiling_flush }

      shared_examples_for 'a successful profile flush' do
        it do
          skip 'Only runs in fully integrated environment.' unless ENV['TEST_DATADOG_INTEGRATION']

          is_expected.to be_a(Datadog::Profiling::Transport::HTTP::Response)
          expect(response.code).to eq(200).or eq(403)
        end
      end

      context 'agent' do
        let(:options) do
          {
            agent_settings: Datadog::Core::Configuration::AgentSettingsResolver::ENVIRONMENT_AGENT_SETTINGS
          }
        end

        it_behaves_like 'a successful profile flush'
      end

      context 'agentless' do
        before do
          skip 'Valid API key must be set.' unless ENV['DD_API_KEY'] && !ENV['DD_API_KEY'].empty?
        end

        let(:options) do
          {
            agent_settings: double('agent_settings which should not be used'),
            site: 'datadoghq.com',
            api_key: ENV['DD_API_KEY'] || 'Invalid API key',
            agentless_allowed: true
          }
        end

        it_behaves_like 'a successful profile flush'
      end
    end
  end
end
