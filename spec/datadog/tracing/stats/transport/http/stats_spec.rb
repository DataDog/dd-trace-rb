# frozen_string_literal: true

require 'datadog/tracing/stats/transport/http/stats'

RSpec.describe Datadog::Tracing::Stats::Transport::HTTP::StatsEndpoint::API::Endpoint do
  subject(:endpoint) { described_class.new('/v0.6/stats') }

  describe '#initialize' do
    it 'sets the verb to :post' do
      expect(endpoint.verb).to eq(:post)
    end

    it 'sets the path to /v0.6/stats' do
      expect(endpoint.path).to eq('/v0.6/stats')
    end
  end

  describe '#encoder' do
    it 'returns nil (encoding is handled externally)' do
      expect(endpoint.encoder).to be_nil
    end
  end
end
