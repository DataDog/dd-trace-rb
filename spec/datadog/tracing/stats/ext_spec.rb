# frozen_string_literal: true

require 'datadog/tracing/stats/ext'

RSpec.describe Datadog::Tracing::Stats::Ext do
  it 'defines ENV_ENABLED' do
    expect(described_class::ENV_ENABLED).to eq('DD_TRACE_STATS_COMPUTATION_ENABLED')
  end

  it 'defines BUCKET_DURATION_NS as 10 seconds in nanoseconds' do
    expect(described_class::BUCKET_DURATION_NS).to eq(10_000_000_000)
  end

  it 'defines trilean values' do
    expect(described_class::TRILEAN_NOT_SET).to eq(0)
    expect(described_class::TRILEAN_TRUE).to eq(1)
    expect(described_class::TRILEAN_FALSE).to eq(2)
  end

  it 'defines gRPC status code tags in priority order' do
    expect(described_class::GRPC_STATUS_CODE_TAGS).to eq([
      'rpc.grpc.status_code',
      'grpc.code',
      'rpc.grpc.status.code',
      'grpc.status.code',
    ])
  end

  it 'defines eligible span kinds' do
    expect(described_class::ELIGIBLE_SPAN_KINDS).to contain_exactly('server', 'client', 'producer', 'consumer')
  end

  it 'defines peer tag span kinds' do
    expect(described_class::PEER_TAG_SPAN_KINDS).to contain_exactly('client', 'producer', 'consumer')
  end

  it 'defines default peer tag keys' do
    expect(described_class::PEER_TAG_KEYS).to include('peer.service', '_dd.base_service')
  end
end
