require 'spec_helper'

require 'msgpack'

require 'datadog/tracing/span'
require 'datadog/tracing/span_event'
require 'datadog/tracing/trace_segment'
require 'datadog/tracing/transport/serializable_trace'

RSpec.describe Datadog::Tracing::Transport::SerializableTrace do
  subject(:serializable_trace) { described_class.new(trace, native_events_supported: native_events_supported) }

  let(:trace) { Datadog::Tracing::TraceSegment.new(spans) }
  let(:native_events_supported) { false }
  let(:spans) do
    Array.new(3) do |i|
      span = Datadog::Tracing::Span.new(
        'job.work',
        resource: 'generate_report',
        service: 'jobs-worker',
        type: 'worker'
      )

      span.set_tag('component', 'sidekiq')
      span.set_tag('job.id', i)
      span
    end
  end

  shared_examples 'serialize all fields' do |include_duration: false, include_native_events: false|
    it 'contains all fields' do
      unpacked_trace.each do |span|
        expected = [
          'span_id',
          'parent_id',
          'trace_id',
          'name',
          'service',
          'resource',
          'type',
          'meta',
          'metrics',
          'meta_struct',
          'span_links',
          'error',
        ]
        if include_duration
          expected << 'start'
          expected << 'duration'
        end
        expected << 'span_events' if include_native_events

        expect(span.keys).to match_array(expected)
      end
    end
  end

  describe '#to_msgpack' do
    subject(:unpacked_trace) { MessagePack.unpack(to_msgpack) }
    let(:to_msgpack) { serializable_trace.to_msgpack }

    context 'when packed then unpacked' do
      let(:original_spans) do
        spans.map do |span|
          Hash[span.to_hash.map { |k, v| [k.to_s, v] }]
        end
      end

      it 'correctly performs a serialization round-trip' do
        is_expected.to eq(original_spans)
      end
    end

    context 'when given trace_id' do
      let(:spans) do
        Array.new(3) do |_i|
          Datadog::Tracing::Span.new(
            'dummy',
            trace_id: trace_id
          )
        end
      end

      context 'when given 64 bits trace id' do
        let(:trace_id) { 0xffffffffffffffff }

        it 'serializes 64 bits trace id entirely' do
          expect(unpacked_trace.map { |s| s['trace_id'] }).to all(eq(0xffffffffffffffff))
        end
      end

      context 'when given 128 bits trace id' do
        let(:trace_id) { 0xaaaaaaaaaaaaaaaaffffffffffffffff }

        it 'serializes the low order 64 bits trace id' do
          expect(unpacked_trace.map { |s| s['trace_id'] }).to all(eq(0xffffffffffffffff))
        end
      end
    end

    context 'when given span links' do
      let(:spans) do
        Array.new(3) do |_i|
          Datadog::Tracing::Span.new(
            'dummy',
            links: [
              Datadog::Tracing::SpanLink.new(
                Datadog::Tracing::TraceDigest.new(
                  trace_id: 0xaaaaaaaaaaaaaaaaffffffffffffffff,
                  span_id: 0x1,
                  trace_state: 'vendor1=value,v2=v,dd=s:1',
                  trace_sampling_priority: 0x1,
                ),
                attributes: { 'link.name' => 'test_link' }
              ),
              Datadog::Tracing::SpanLink.new(
                Datadog::Tracing::TraceDigest.new(
                  trace_id: 0xa0123456789abcdef,
                  span_id: 0x2,
                ),
              ),
              Datadog::Tracing::SpanLink.new(
                Datadog::Tracing::TraceDigest.new,
              )
            ],
          )
        end
      end

      it 'serializes span links' do
        expect(
          unpacked_trace.map do |s|
            s['span_links']
          end
        ).to all(
          eq(
            [{
              'span_id' => 1,
              'trace_id' => 0xffffffffffffffff,
              'trace_id_high' => 0xaaaaaaaaaaaaaaaa,
              'attributes' => { 'link.name' => 'test_link' },
              'flags' => 2147483649,
              'tracestate' => 'vendor1=value,v2=v,dd=s:1',
            },
             {
               'span_id' => 2,
               'trace_id' => 0x0123456789abcdef,
               'trace_id_high' => 10,
               'flags' => 0
             },
             { 'span_id' => 0, 'trace_id' => 0, 'flags' => 0 }]
          )
        )
      end
    end

    context 'when given span events' do
      let(:spans) do
        Array.new(2) do |i|
          Datadog::Tracing::Span.new(
            'dummy',
            events: [
              Datadog::Tracing::SpanEvent.new(
                'First Event',
                time_unix_nano: 123
              ),
              Datadog::Tracing::SpanEvent.new(
                "Another Event #{i}!",
                time_unix_nano: 456,
                attributes: { id: i, required: (i == 1) },
              ),
            ],
          )
        end
      end

      it 'serializes span events' do
        expect(
          unpacked_trace.map do |s|
            s['meta']['events']
          end
        ).to eq(
          [
            '[{"name":"First Event","time_unix_nano":123},{"name":"Another Event 0!","time_unix_nano":456,' \
            '"attributes":{"id":0,"required":false}}]',
            '[{"name":"First Event","time_unix_nano":123},{"name":"Another Event 1!","time_unix_nano":456,' \
            '"attributes":{"id":1,"required":true}}]',
          ]
        )
      end

      it_behaves_like 'serialize all fields'

      context 'when native events are supported' do
        let(:native_events_supported) { true }

        it 'serializes span events as top-level field' do
          expect(
            unpacked_trace.map do |s|
              s['span_events']
            end
          ).to eq(
            [
              [
                { 'name' => 'First Event', 'time_unix_nano' => 123 },
                { 'name' => 'Another Event 0!', 'time_unix_nano' => 456, 'attributes' => {
                  'id' => { 'int_value' => 0, 'type' => 2 }, 'required' => { 'bool_value' => false, 'type' => 1 }
                } }
              ],
              [
                { 'name' => 'First Event', 'time_unix_nano' => 123 },
                { 'name' => 'Another Event 1!', 'time_unix_nano' => 456, 'attributes' => {
                  'id' => { 'int_value' => 1, 'type' => 2 }, 'required' => { 'bool_value' => true, 'type' => 1 }
                } }
              ],
            ]
          )
        end

        it_behaves_like 'serialize all fields', include_native_events: true
      end
    end

    it_behaves_like 'serialize all fields'
  end

  describe '#to_json' do
    subject(:to_json) { serializable_trace.to_json }

    context 'when dumped and parsed' do
      subject(:unpacked_trace) { JSON(to_json) }

      let(:original_spans) do
        spans.map do |span|
          Hash[span.to_hash.map { |k, v| [k.to_s, v] }]
        end
      end

      it 'correctly performs a serialization round-trip' do
        is_expected.to eq(original_spans)
      end
    end

    context 'when given trace_id' do
      subject(:unpacked_trace) { JSON(to_json) }

      let(:spans) do
        Array.new(3) do |_i|
          Datadog::Tracing::Span.new(
            'dummy',
            trace_id: trace_id
          )
        end
      end

      context 'when given 64 bits trace id' do
        let(:trace_id) { 0xffffffffffffffff }

        it 'serializes 64 bits trace id entirely' do
          expect(unpacked_trace.map { |s| s['trace_id'] }).to all(eq(0xffffffffffffffff))
        end
      end

      context 'when given 128 bits trace id' do
        let(:trace_id) { 0xaaaaaaaaaaaaaaaaffffffffffffffff }

        it 'serializes the low order 64 bits trace id' do
          expect(unpacked_trace.map { |s| s['trace_id'] }).to all(eq(0xffffffffffffffff))
        end
      end
    end
  end
end
