# frozen_string_literal: true

require 'msgpack'
require 'datadog/core'
require 'datadog/core/ddsketch'
require 'datadog/tracing/stats/serializer'
require 'datadog/tracing/stats/aggregation_key'
require 'datadog/tracing/stats/ext'

RSpec.describe Datadog::Tracing::Stats::Serializer do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:key) do
    Datadog::Tracing::Stats::AggregationKey.new(
      service: 'web-service',
      name: 'rack.request',
      resource: 'GET /users',
      type: 'web',
      http_status_code: 200,
      grpc_status_code: 0,
      span_kind: 'server',
      synthetics: false,
      is_trace_root: Datadog::Tracing::Stats::Ext::TRILEAN_TRUE,
      peer_tags: [],
      http_method: 'GET',
      http_endpoint: '/users',
    )
  end

  let(:group_stats) do
    {
      hits: 10,
      errors: 2,
      duration: 5_000_000_000,
      top_level_hits: 8,
      ok_distribution: Datadog::Core::DDSketch.new,
      error_distribution: Datadog::Core::DDSketch.new,
    }
  end

  let(:bucket_time) { 1700000000_000_000_000 }

  let(:flushed_buckets) do
    {bucket_time => {key => group_stats}}
  end

  describe '.serialize' do
    subject(:payload) do
      described_class.serialize(
        flushed_buckets,
        env: 'production',
        service: 'web-service',
        version: '1.0.0',
        runtime_id: 'abc-123',
        sequence: 42,
        container_id: 'container-xyz',
      )
    end

    it 'produces a ClientStatsPayload hash with all required fields' do
      expect(payload).to include(
        'Env' => 'production',
        'Version' => '1.0.0',
        'Lang' => 'ruby',
        'RuntimeID' => 'abc-123',
        'Sequence' => 42,
        'Service' => 'web-service',
        'ContainerID' => 'container-xyz',
        'AgentAggregation' => '',
        'Tags' => [],
      )
      expect(payload['Hostname']).to be_a(String)
      expect(payload['TracerVersion']).to eq(Datadog::VERSION::STRING)
    end

    it 'serializes buckets' do
      expect(payload['Stats']).to be_an(Array)
      expect(payload['Stats'].length).to eq(1)
    end

    context 'with nil env/service/version' do
      subject(:payload) do
        described_class.serialize(
          flushed_buckets,
          env: nil,
          service: nil,
          version: nil,
        )
      end

      it 'defaults to empty strings' do
        expect(payload['Env']).to eq('')
        expect(payload['Service']).to eq('')
        expect(payload['Version']).to eq('')
      end
    end
  end

  describe '.serialize_buckets' do
    subject(:buckets) { described_class.serialize_buckets(flushed_buckets) }

    it 'returns an array of ClientStatsBucket hashes' do
      expect(buckets.length).to eq(1)
      bucket = buckets.first

      expect(bucket['Start']).to eq(bucket_time)
      expect(bucket['Duration']).to eq(Datadog::Tracing::Stats::Ext::BUCKET_DURATION_NS)
      expect(bucket['Stats']).to be_an(Array)
    end
  end

  describe '.serialize_groups' do
    subject(:groups) { described_class.serialize_groups({key => group_stats}) }

    it 'returns an array of ClientGroupedStats hashes' do
      expect(groups.length).to eq(1)
      group = groups.first

      expect(group['Service']).to eq('web-service')
      expect(group['Name']).to eq('rack.request')
      expect(group['Resource']).to eq('GET /users')
      expect(group['Type']).to eq('web')
      expect(group['HTTPStatusCode']).to eq(200)
      expect(group['GRPCStatusCode']).to eq(0)
      expect(group['SpanKind']).to eq('server')
      expect(group['Synthetics']).to eq(false)
      expect(group['IsTraceRoot']).to eq(Datadog::Tracing::Stats::Ext::TRILEAN_TRUE)
      expect(group['PeerTags']).to eq([])
      expect(group['HTTPMethod']).to eq('GET')
      expect(group['HTTPEndpoint']).to eq('/users')
      expect(group['Hits']).to eq(10)
      expect(group['Errors']).to eq(2)
      expect(group['Duration']).to eq(5_000_000_000)
      expect(group['TopLevelHits']).to eq(8)
      expect(group['DBType']).to eq('')
      expect(group['OkSummary']).to be_a(String)
      expect(group['ErrorSummary']).to be_a(String)
    end
  end

  describe '.encode' do
    it 'produces valid msgpack bytes' do
      payload = described_class.serialize(flushed_buckets, env: 'test', service: 'test')
      encoded = described_class.encode(payload)

      expect(encoded).to be_a(String)
      decoded = MessagePack.unpack(encoded)
      expect(decoded['Env']).to eq('test')
      expect(decoded['Stats']).to be_an(Array)
    end
  end

  describe '.encode_sketch' do
    it 'returns encoded bytes for a DDSketch' do
      sketch = Datadog::Core::DDSketch.new
      sketch.add(1.0)
      sketch.add(2.0)

      encoded = described_class.encode_sketch(sketch)
      expect(encoded).to be_a(String)
    end

    it 'returns empty binary string for unsupported sketches' do
      fake_sketch = double('sketch')
      allow(fake_sketch).to receive(:respond_to?).with(:encode).and_return(false)

      encoded = described_class.encode_sketch(fake_sketch)
      expect(encoded).to eq(''.b)
    end
  end
end
