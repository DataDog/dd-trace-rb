# frozen_string_literal: true

require 'datadog/tracing/stats/aggregation_key'
require 'datadog/tracing/stats/ext'

RSpec.describe Datadog::Tracing::Stats::AggregationKey do
  subject(:key) do
    described_class.new(
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

  describe '#initialize' do
    it 'stores all 12 aggregation dimensions' do
      expect(key.service).to eq('web-service')
      expect(key.name).to eq('rack.request')
      expect(key.resource).to eq('GET /users')
      expect(key.type).to eq('web')
      expect(key.http_status_code).to eq(200)
      expect(key.grpc_status_code).to eq(0)
      expect(key.span_kind).to eq('server')
      expect(key.synthetics).to eq(false)
      expect(key.is_trace_root).to eq(Datadog::Tracing::Stats::Ext::TRILEAN_TRUE)
      expect(key.peer_tags).to eq([])
      expect(key.http_method).to eq('GET')
      expect(key.http_endpoint).to eq('/users')
    end

    context 'with nil values' do
      subject(:key) { described_class.new(service: nil, name: nil, resource: nil) }

      it 'defaults nil strings to empty strings' do
        expect(key.service).to eq('')
        expect(key.name).to eq('')
        expect(key.resource).to eq('')
        expect(key.type).to eq('')
        expect(key.span_kind).to eq('')
        expect(key.http_method).to eq('')
        expect(key.http_endpoint).to eq('')
      end

      it 'defaults nil integers to 0' do
        expect(key.http_status_code).to eq(0)
        expect(key.grpc_status_code).to eq(0)
      end

      it 'defaults is_trace_root to TRILEAN_NOT_SET' do
        expect(key.is_trace_root).to eq(Datadog::Tracing::Stats::Ext::TRILEAN_NOT_SET)
      end

      it 'defaults peer_tags to empty array' do
        expect(key.peer_tags).to eq([])
      end
    end
  end

  describe '#==' do
    let(:same_key) do
      described_class.new(
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

    let(:different_key) do
      described_class.new(
        service: 'other-service',
        name: 'rack.request',
        resource: 'GET /users',
      )
    end

    it 'considers keys with same dimensions equal' do
      expect(key).to eq(same_key)
    end

    it 'considers keys with different dimensions not equal' do
      expect(key).not_to eq(different_key)
    end

    it 'returns false for non-AggregationKey objects' do
      expect(key).not_to eq('not a key')
    end
  end

  describe '#hash' do
    let(:same_key) do
      described_class.new(
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

    it 'produces the same hash for equal keys' do
      expect(key.hash).to eq(same_key.hash)
    end

    it 'can be used as a hash key' do
      h = {key => 'value'}
      expect(h[same_key]).to eq('value')
    end
  end
end
