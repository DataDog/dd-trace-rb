require 'spec_helper'

require 'msgpack'

require 'datadog/tracing/span'
require 'datadog/tracing/trace_segment'
require 'ddtrace/transport/serializable_trace'

RSpec.describe Datadog::Transport::SerializableTrace do
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
  end
end
