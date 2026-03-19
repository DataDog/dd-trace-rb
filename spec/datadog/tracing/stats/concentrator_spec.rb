# frozen_string_literal: true

require 'datadog/core'
require 'datadog/core/ddsketch'
require 'datadog/tracing/span'
require 'datadog/tracing/stats/concentrator'
require 'datadog/tracing/stats/ext'
require 'datadog/tracing/metadata/ext'

RSpec.describe Datadog::Tracing::Stats::Concentrator do
  before do
    skip_if_libdatadog_not_supported
  end

  subject(:concentrator) { described_class.new }

  let(:now) { Time.now }

  def build_span(
    name: 'test.span',
    service: 'test-svc',
    resource: 'GET /test',
    type: 'web',
    start_time: now - 1,
    duration: 0.5,
    parent_id: 0,
    status: 0,
    meta: {},
    metrics: {}
  )
    span = Datadog::Tracing::Span.new(
      name,
      service: service,
      resource: resource,
      type: type,
      start_time: start_time,
      duration: duration,
      parent_id: parent_id,
      status: status,
    )
    span.instance_variable_set(:@end_time, start_time + duration)
    meta.each { |k, v| span.set_tag(k, v) }
    metrics.each { |k, v| span.set_metric(k, v) }
    span
  end

  describe '#add_span' do
    context 'with an eligible top-level span' do
      let(:span) do
        build_span(
          metrics: {Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL => 1.0},
        )
      end

      it 'adds the span to a bucket' do
        concentrator.add_span(span)
        expect(concentrator.buckets).not_to be_empty
      end

      it 'increments hits' do
        concentrator.add_span(span)
        group = first_group
        expect(group[:hits]).to eq(1)
      end

      it 'increments top_level_hits for top-level spans' do
        concentrator.add_span(span)
        group = first_group
        expect(group[:top_level_hits]).to eq(1)
      end

      it 'accumulates duration' do
        concentrator.add_span(span)
        group = first_group
        expect(group[:duration]).to be > 0
      end

      it 'records ok distribution for non-error spans' do
        concentrator.add_span(span)
        group = first_group
        # DDSketch should have recorded a value
        expect(group[:ok_distribution]).to be_a(Datadog::Core::DDSketch)
      end
    end

    context 'with an error span' do
      let(:span) do
        build_span(
          status: Datadog::Tracing::Metadata::Ext::Errors::STATUS,
          metrics: {Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL => 1.0},
        )
      end

      it 'increments errors counter' do
        concentrator.add_span(span)
        group = first_group
        expect(group[:errors]).to eq(1)
      end

      it 'records error distribution' do
        concentrator.add_span(span)
        group = first_group
        expect(group[:error_distribution]).to be_a(Datadog::Core::DDSketch)
      end
    end

    context 'with a non-eligible span' do
      let(:span) { build_span }

      it 'does not add the span to any bucket' do
        concentrator.add_span(span)
        expect(concentrator.buckets).to be_empty
      end
    end

    context 'with a measured span' do
      let(:span) do
        build_span(
          metrics: {Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED => 1.0},
        )
      end

      it 'adds the span' do
        concentrator.add_span(span)
        expect(concentrator.buckets).not_to be_empty
      end

      it 'does not count as top-level' do
        concentrator.add_span(span)
        group = first_group
        expect(group[:top_level_hits]).to eq(0)
      end
    end

    context 'with a span having eligible span.kind' do
      let(:span) do
        build_span(meta: {'span.kind' => 'server'})
      end

      it 'adds the span' do
        concentrator.add_span(span)
        expect(concentrator.buckets).not_to be_empty
      end
    end

    context 'with partial flush' do
      let(:span) do
        build_span(
          metrics: {Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL => 1.0},
        )
      end

      it 'excludes partial spans' do
        concentrator.add_span(span, partial: true)
        expect(concentrator.buckets).to be_empty
      end
    end

    context 'with multiple spans in the same bucket and key' do
      it 'aggregates hits' do
        3.times do
          span = build_span(
            metrics: {Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL => 1.0},
          )
          concentrator.add_span(span)
        end

        group = first_group
        expect(group[:hits]).to eq(3)
        expect(group[:top_level_hits]).to eq(3)
      end
    end
  end

  describe '#flush' do
    let(:span) do
      build_span(
        start_time: now - 15,
        duration: 0.5,
        metrics: {Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL => 1.0},
      )
    end

    before { concentrator.add_span(span) }

    context 'when bucket is complete' do
      it 'returns the completed buckets' do
        now_ns = (now.to_f * 1e9).to_i
        flushed = concentrator.flush(now_ns: now_ns)
        expect(flushed).not_to be_empty
      end

      it 'removes flushed buckets from internal state' do
        now_ns = (now.to_f * 1e9).to_i
        concentrator.flush(now_ns: now_ns)
        expect(concentrator.buckets).to be_empty
      end
    end

    context 'when force flushing' do
      let(:span) do
        build_span(
          start_time: now - 1,
          duration: 0.5,
          metrics: {Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL => 1.0},
        )
      end

      it 'flushes all buckets including current' do
        now_ns = (now.to_f * 1e9).to_i
        flushed = concentrator.flush(now_ns: now_ns, force: true)
        expect(flushed).not_to be_empty
        expect(concentrator.buckets).to be_empty
      end
    end

    context 'when no data has been added' do
      subject(:empty_concentrator) { described_class.new }

      it 'returns empty hash' do
        flushed = empty_concentrator.flush(now_ns: (now.to_f * 1e9).to_i)
        expect(flushed).to be_empty
      end
    end
  end

  describe '#agent_peer_tags=' do
    it 'updates the peer tags used for key building' do
      concentrator.agent_peer_tags = ['custom.tag']
      # Test that peer tags are used when building keys for client spans
      span = build_span(
        meta: {'span.kind' => 'client', 'custom.tag' => 'value'},
        metrics: {Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL => 1.0},
      )
      concentrator.add_span(span)

      group_key = first_key
      expect(group_key.peer_tags).to include('custom.tag:value')
    end
  end

  private

  def first_group
    _, groups = concentrator.buckets.first
    _, group = groups.first
    group
  end

  def first_key
    _, groups = concentrator.buckets.first
    key, _ = groups.first
    key
  end
end
