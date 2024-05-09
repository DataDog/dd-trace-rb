require 'spec_helper'

require 'msgpack'

require 'datadog/tracing/span'
require 'datadog/tracing/trace_segment'
require 'datadog/tracing/transport/serializable_trace'

RSpec.describe Datadog::Tracing::Transport::SerializableTrace do
  subject(:serializable_trace) { described_class.new(trace) }

  let(:trace) { Datadog::Tracing::TraceSegment.new(spans) }
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

  describe '#to_msgpack' do
    subject(:to_msgpack) { serializable_trace.to_msgpack }

    context 'when packed then upacked' do
      subject(:unpacked_trace) { MessagePack.unpack(to_msgpack) }

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
      subject(:unpacked_trace) { MessagePack.unpack(to_msgpack) }

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
      subject(:unpacked_trace) { MessagePack.unpack(to_msgpack) }

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
