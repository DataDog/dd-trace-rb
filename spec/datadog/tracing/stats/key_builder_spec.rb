# frozen_string_literal: true

require 'datadog/tracing/span'
require 'datadog/tracing/stats/key_builder'
require 'datadog/tracing/stats/ext'
require 'datadog/tracing/metadata/ext'

RSpec.describe Datadog::Tracing::Stats::KeyBuilder do
  let(:span) do
    Datadog::Tracing::Span.new(
      'rack.request',
      service: 'web-service',
      resource: 'GET /users',
      type: 'web',
      parent_id: 0,
    )
  end

  describe '.build' do
    before do
      span.set_tag('http.status_code', '200')
      span.set_tag('http.method', 'GET')
      span.set_tag('http.endpoint', '/users')
      span.set_tag('span.kind', 'server')
    end

    it 'builds an AggregationKey with all 12 dimensions' do
      key = described_class.build(span)

      expect(key.service).to eq('web-service')
      expect(key.name).to eq('rack.request')
      expect(key.resource).to eq('GET /users')
      expect(key.type).to eq('web')
      expect(key.http_status_code).to eq(200)
      expect(key.span_kind).to eq('server')
      expect(key.is_trace_root).to eq(Datadog::Tracing::Stats::Ext::TRILEAN_TRUE)
      expect(key.synthetics).to eq(false)
      expect(key.http_method).to eq('GET')
      expect(key.http_endpoint).to eq('/users')
    end

    context 'with synthetics flag' do
      it 'sets synthetics dimension' do
        key = described_class.build(span, synthetics: true)
        expect(key.synthetics).to eq(true)
      end
    end
  end

  describe '.extract_http_status_code' do
    it 'extracts the HTTP status code from meta' do
      span.set_tag('http.status_code', '404')
      expect(described_class.extract_http_status_code(span)).to eq(404)
    end

    it 'returns 0 when not present' do
      expect(described_class.extract_http_status_code(span)).to eq(0)
    end
  end

  describe '.extract_grpc_status_code' do
    it 'extracts from rpc.grpc.status_code (highest priority)' do
      span.set_tag('rpc.grpc.status_code', '2')
      span.set_tag('grpc.code', '3')
      expect(described_class.extract_grpc_status_code(span)).to eq(2)
    end

    it 'falls back to grpc.code' do
      span.set_tag('grpc.code', '5')
      expect(described_class.extract_grpc_status_code(span)).to eq(5)
    end

    it 'falls back to rpc.grpc.status.code' do
      span.set_tag('rpc.grpc.status.code', '14')
      expect(described_class.extract_grpc_status_code(span)).to eq(14)
    end

    it 'falls back to grpc.status.code' do
      span.set_tag('grpc.status.code', '7')
      expect(described_class.extract_grpc_status_code(span)).to eq(7)
    end

    it 'returns 0 when no gRPC tag is present' do
      expect(described_class.extract_grpc_status_code(span)).to eq(0)
    end
  end

  describe '.extract_is_trace_root' do
    it 'returns TRILEAN_TRUE when parent_id is 0' do
      expect(described_class.extract_is_trace_root(span)).to eq(
        Datadog::Tracing::Stats::Ext::TRILEAN_TRUE
      )
    end

    it 'returns TRILEAN_FALSE when parent_id is non-zero' do
      child_span = Datadog::Tracing::Span.new('child', parent_id: 12345)
      expect(described_class.extract_is_trace_root(child_span)).to eq(
        Datadog::Tracing::Stats::Ext::TRILEAN_FALSE
      )
    end
  end

  describe '.extract_peer_tags' do
    context 'with client span kind' do
      before { span.set_tag('span.kind', 'client') }

      it 'collects peer tags from the span' do
        span.set_tag('peer.service', 'postgres')
        span.set_tag('db.name', 'users_db')

        tags = described_class.extract_peer_tags(span, nil)
        expect(tags).to include('db.name:users_db', 'peer.service:postgres')
      end

      it 'returns sorted tags' do
        span.set_tag('peer.service', 'redis')
        span.set_tag('db.system', 'redis')

        tags = described_class.extract_peer_tags(span, nil)
        expect(tags).to eq(tags.sort)
      end

      it 'uses agent-provided peer tag keys when available' do
        span.set_tag('peer.service', 'postgres')
        span.set_tag('custom.tag', 'value')

        agent_tags = ['peer.service', 'custom.tag']
        tags = described_class.extract_peer_tags(span, agent_tags)
        expect(tags).to include('peer.service:postgres', 'custom.tag:value')
      end
    end

    context 'with server span kind' do
      before { span.set_tag('span.kind', 'server') }

      it 'returns empty array (server spans do not use peer tags)' do
        span.set_tag('peer.service', 'postgres')
        expect(described_class.extract_peer_tags(span, nil)).to eq([])
      end
    end

    context 'with internal span kind and _dd.base_service override' do
      before do
        span.set_tag('span.kind', 'internal')
        span.set_tag('_dd.base_service', 'original-service')
      end

      it 'collects peer tags (service override scenario)' do
        span.set_tag('peer.service', 'downstream')
        tags = described_class.extract_peer_tags(span, nil)
        expect(tags).to include('_dd.base_service:original-service')
      end
    end

    context 'with producer span kind' do
      before { span.set_tag('span.kind', 'producer') }

      it 'collects peer tags' do
        span.set_tag('peer.service', 'kafka')
        tags = described_class.extract_peer_tags(span, nil)
        expect(tags).to include('peer.service:kafka')
      end
    end

    context 'with consumer span kind' do
      before { span.set_tag('span.kind', 'consumer') }

      it 'collects peer tags' do
        span.set_tag('peer.service', 'rabbitmq')
        tags = described_class.extract_peer_tags(span, nil)
        expect(tags).to include('peer.service:rabbitmq')
      end
    end
  end

  describe '.extract_span_kind' do
    it 'returns the span kind' do
      span.set_tag('span.kind', 'server')
      expect(described_class.extract_span_kind(span)).to eq('server')
    end

    it 'returns empty string when not set' do
      expect(described_class.extract_span_kind(span)).to eq('')
    end
  end

  describe '.extract_http_method' do
    it 'returns the HTTP method' do
      span.set_tag('http.method', 'POST')
      expect(described_class.extract_http_method(span)).to eq('POST')
    end

    it 'returns empty string when not set' do
      expect(described_class.extract_http_method(span)).to eq('')
    end
  end

  describe '.extract_http_endpoint' do
    it 'returns the HTTP endpoint' do
      span.set_tag('http.endpoint', '/api/v1/users')
      expect(described_class.extract_http_endpoint(span)).to eq('/api/v1/users')
    end

    it 'returns empty string when not set' do
      expect(described_class.extract_http_endpoint(span)).to eq('')
    end
  end
end
