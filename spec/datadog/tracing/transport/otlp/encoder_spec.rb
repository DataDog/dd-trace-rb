# frozen_string_literal: true

require 'spec_helper'

require 'base64'
require 'json'

require 'datadog/tracing/span'
require 'datadog/tracing/span_event'
require 'datadog/tracing/trace_segment'
require 'datadog/tracing/transport/otlp/encoder'

RSpec.describe Datadog::Tracing::Transport::OTLP::Encoder do
  subject(:encoder) do
    described_class.new(
      resource_attributes: resource_attributes,
      scope_version: scope_version,
      default_service: default_service
    )
  end

  let(:resource_attributes) { [{key: 'service.name', value: {stringValue: 'my-service'}}] }
  let(:scope_version) { '9.9.9' }
  let(:default_service) { 'my-service' }

  let(:trace) { Datadog::Tracing::TraceSegment.new(spans, sampling_priority: 1) }

  # A single fully-populated span, used as the base case for most assertions.
  let(:spans) { [span] }
  let(:span) do
    s = Datadog::Tracing::Span.new(
      'web.request',
      service: 'my-service',
      resource: 'GET /users',
      type: 'web',
      id: 0x0123456789abcdef,
      trace_id: 0xaabbccddeeff00112233445566778899,
      parent_id: 0xfedcba9876543210,
      status: 1
    )
    s.start_time = Time.at(1_700_000_000, 500_000) # 1_700_000_000.0005s => 1700000000500000000ns
    s.duration = 1.5
    s.meta['span.kind'] = 'server'
    s.meta['error.message'] = 'boom'
    s.meta['http.method'] = 'GET'
    s.metrics['custom.count'] = 42.0
    s.metrics['custom.ratio'] = 0.75
    s
  end

  describe '#payload' do
    subject(:payload) { encoder.payload(trace) }

    let(:resource_spans) { payload[:resourceSpans] }
    let(:scope_spans) { resource_spans.first[:scopeSpans] }
    let(:otlp_spans) { scope_spans.first[:spans] }
    let(:otlp_span) { otlp_spans.first }

    it 'wraps spans in the resourceSpans/scopeSpans envelope' do
      expect(resource_spans.length).to eq(1)
      expect(resource_spans.first[:resource]).to eq(attributes: resource_attributes)
      expect(scope_spans.length).to eq(1)
    end

    it 'sets the instrumentation scope to dd-trace-rb and the gem version' do
      expect(scope_spans.first[:scope]).to eq(name: 'dd-trace-rb', version: '9.9.9')
    end

    it 'encodes the 128-bit trace id as 32 lowercase hex chars' do
      expect(otlp_span[:traceId]).to eq('aabbccddeeff00112233445566778899')
    end

    it 'encodes span id and parent span id as 16 lowercase hex chars' do
      expect(otlp_span[:spanId]).to eq('0123456789abcdef')
      expect(otlp_span[:parentSpanId]).to eq('fedcba9876543210')
    end

    it 'uses the DD resource as the OTLP span name' do
      expect(otlp_span[:name]).to eq('GET /users')
    end

    it 'computes start and end times in nanoseconds' do
      expect(otlp_span[:startTimeUnixNano]).to eq(1_700_000_000_500_000_000)
      expect(otlp_span[:endTimeUnixNano]).to eq(1_700_000_000_500_000_000 + 1_500_000_000)
    end

    describe 'attributes' do
      subject(:attributes) { otlp_span[:attributes] }

      it 'adds resource.name and operation.name' do
        expect(attributes).to include(
          {key: 'resource.name', value: {stringValue: 'GET /users'}},
          {key: 'operation.name', value: {stringValue: 'web.request'}}
        )
      end

      it 'adds span.type' do
        expect(attributes).to include({key: 'span.type', value: {stringValue: 'web'}})
      end

      it 'maps meta entries to stringValue attributes' do
        expect(attributes).to include(
          {key: 'error.message', value: {stringValue: 'boom'}},
          {key: 'http.method', value: {stringValue: 'GET'}}
        )
      end

      it 'maps integral metrics to intValue (string-encoded) and fractional metrics to doubleValue' do
        expect(attributes).to include(
          {key: 'custom.count', value: {intValue: '42'}},
          {key: 'custom.ratio', value: {doubleValue: 0.75}}
        )
      end

      it 'omits service.name when the span service matches the default service' do
        expect(attributes).not_to include(a_hash_including(key: 'service.name'))
      end

      it 'does not emit span.kind or _dd.p.tid as attributes' do
        keys = attributes.map { |a| a[:key] }
        expect(keys).not_to include('span.kind')
        expect(keys).not_to include('_dd.p.tid')
      end
    end

    describe 'service.name attribute' do
      before { span.service = 'other-service' }

      it 'is emitted when the span service differs from the default service' do
        expect(otlp_span[:attributes]).to include({key: 'service.name', value: {stringValue: 'other-service'}})
      end
    end

    describe 'kind' do
      subject(:kind) { otlp_span[:kind] }

      context 'with span.kind meta' do
        before { span.meta['span.kind'] = 'client' }

        it { is_expected.to eq(described_class::SPAN_KIND_CLIENT) }
      end

      context 'with an unknown span.kind meta' do
        before { span.meta['span.kind'] = 'bogus' }

        it { is_expected.to eq(described_class::SPAN_KIND_UNSPECIFIED) }
      end

      context 'without span.kind meta, falling back to type' do
        before do
          span.meta.delete('span.kind')
          span.type = 'http'
        end

        it { is_expected.to eq(described_class::SPAN_KIND_SERVER) }
      end

      context 'without span.kind meta and an unmapped type' do
        before do
          span.meta.delete('span.kind')
          span.type = 'custom'
        end

        it { is_expected.to eq(described_class::SPAN_KIND_INTERNAL) }
      end

      context 'without span.kind meta and no type' do
        before do
          span.meta.delete('span.kind')
          span.type = nil
        end

        it { is_expected.to eq(described_class::SPAN_KIND_UNSPECIFIED) }
      end
    end

    describe 'status' do
      subject(:status) { otlp_span[:status] }

      context 'when the span has an error' do
        it 'is ERROR with the error message' do
          expect(status).to eq(code: described_class::STATUS_CODE_ERROR, message: 'boom')
        end
      end

      context 'when the span has no error' do
        before { span.status = 0 }

        it 'is UNSET' do
          expect(status).to eq(code: described_class::STATUS_CODE_UNSET)
        end
      end
    end

    describe 'parentSpanId' do
      context 'when the span is a root span (parent_id 0)' do
        before { span.parent_id = 0 }

        it 'is omitted' do
          expect(otlp_span).not_to have_key(:parentSpanId)
        end
      end
    end

    describe 'trace id with _dd.p.tid' do
      let(:span) do
        s = Datadog::Tracing::Span.new(
          'rpc',
          service: 'my-service',
          resource: 'rpc',
          id: 0xff,
          trace_id: 0x1122334455667788,
          parent_id: 0
        )
        s.start_time = Time.at(1_700_000_000, 0)
        s.duration = 0.000_001
        s.meta['_dd.p.tid'] = '00000000aabbccdd'
        s
      end

      it 'takes the upper 64 bits from the _dd.p.tid meta' do
        expect(otlp_span[:traceId]).to eq('00000000aabbccdd1122334455667788')
      end
    end

    describe 'meta_struct' do
      let(:span) do
        s = Datadog::Tracing::Span.new('op', service: 'my-service', resource: 'op', id: 1, trace_id: 2)
        s.start_time = Time.at(1_700_000_000, 0)
        s.duration = 0.0
        s.metastruct['appsec'] = {'rule' => 'x'}
        s
      end

      it 'encodes meta_struct entries as base64 bytesValue' do
        attr = otlp_span[:attributes].find { |a| a[:key] == 'appsec' }
        expect(attr).not_to be_nil
        decoded = JSON.parse(Base64.strict_decode64(attr[:value][:bytesValue]))
        expect(decoded).to eq('rule' => 'x')
      end
    end

    describe 'span links' do
      let(:digest) do
        Datadog::Tracing::TraceDigest.new(
          span_id: 0xaaaa,
          trace_id: 0xbbbb,
          trace_state: 'dd=s:1',
          trace_sampling_priority: 1
        )
      end
      let(:span) do
        s = Datadog::Tracing::Span.new(
          'op',
          service: 'my-service',
          resource: 'op',
          id: 1,
          trace_id: 2,
          links: [Datadog::Tracing::SpanLink.new(digest, attributes: {'link.attr' => 'v'})]
        )
        s.start_time = Time.at(1_700_000_000, 0)
        s.duration = 0.0
        s
      end

      it 'encodes links with hex traceId/spanId, attributes and traceState' do
        links = otlp_span[:links]
        expect(links.length).to eq(1)
        link = links.first
        expect(link[:traceId]).to eq(format('%032x', 0xbbbb))
        expect(link[:spanId]).to eq('000000000000aaaa')
        expect(link[:traceState]).to eq('dd=s:1')
        expect(link[:attributes]).to include({key: 'link.attr', value: {stringValue: 'v'}})
      end
    end

    describe 'span events' do
      let(:span) do
        s = Datadog::Tracing::Span.new(
          'op',
          service: 'my-service',
          resource: 'op',
          id: 1,
          trace_id: 2,
          events: [
            Datadog::Tracing::SpanEvent.new(
              'exception',
              attributes: {'count' => 3, 'ok' => true, 'tags' => %w[a b]},
              time_unix_nano: 1_700_000_000_000_000_000
            ),
          ]
        )
        s.start_time = Time.at(1_700_000_000, 0)
        s.duration = 0.0
        s
      end

      it 'encodes events with timeUnixNano, name and typed attributes' do
        events = otlp_span[:events]
        expect(events.length).to eq(1)
        event = events.first
        expect(event[:timeUnixNano]).to eq(1_700_000_000_000_000_000)
        expect(event[:name]).to eq('exception')
        expect(event[:attributes]).to include(
          {key: 'count', value: {intValue: '3'}},
          {key: 'ok', value: {boolValue: true}},
          {key: 'tags', value: {arrayValue: {values: [{stringValue: 'a'}, {stringValue: 'b'}]}}}
        )
      end
    end
  end

  describe '#encode' do
    subject(:encoded) { encoder.encode(trace) }

    it 'returns a JSON string matching #payload' do
      expect(JSON.parse(encoded)).to eq(JSON.parse(JSON.dump(encoder.payload(trace))))
    end

    it 'uses lowerCamelCase top-level keys' do
      parsed = JSON.parse(encoded)
      expect(parsed).to have_key('resourceSpans')
      expect(parsed['resourceSpans'].first).to have_key('scopeSpans')
    end
  end
end
