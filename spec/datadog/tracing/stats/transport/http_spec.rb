# frozen_string_literal: true

require 'datadog/core'
require 'datadog/tracing/stats/transport/http'

RSpec.describe Datadog::Tracing::Stats::Transport::HTTP do
  describe '.default' do
    let(:agent_settings) do
      Datadog::Core::Configuration::AgentSettings.new(
        adapter: :net_http,
        hostname: 'localhost',
        port: 8126,
      )
    end
    let(:logger) { instance_double(Datadog::Core::Logger) }

    it 'builds a transport for /v0.6/stats' do
      transport = described_class.default(agent_settings: agent_settings, logger: logger)
      expect(transport).to be_a(Datadog::Tracing::Stats::Transport::StatsTransport::Transport)
      expect(transport.current_api_id).to eq('v0.6')
    end

    it 'responds to send_stats' do
      transport = described_class.default(agent_settings: agent_settings, logger: logger)
      expect(transport).to respond_to(:send_stats)
    end

    it 'configures the transport with correct API endpoint' do
      transport = described_class.default(agent_settings: agent_settings, logger: logger)
      api = transport.apis['v0.6']
      expect(api).to be_a_kind_of(Datadog::Core::Transport::HTTP::API::Instance)
      expect(api.endpoint.path).to eq('/v0.6/stats')
    end
  end
end
