# frozen_string_literal: true

require 'datadog/tracing/span'
require 'datadog/tracing/stats/span_eligibility'
require 'datadog/tracing/metadata/ext'

RSpec.describe Datadog::Tracing::Stats::SpanEligibility do
  let(:span) do
    Datadog::Tracing::Span.new(
      'test.span',
      service: 'test-service',
      resource: 'test-resource',
    )
  end

  describe '.eligible?' do
    context 'when span is a partial flush snapshot' do
      it 'returns false' do
        span.set_metric(Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL, 1.0)
        expect(described_class.eligible?(span, partial: true)).to be false
      end
    end

    context 'when span is top-level' do
      before { span.set_metric(Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL, 1.0) }

      it 'returns true' do
        expect(described_class.eligible?(span)).to be true
      end
    end

    context 'when span is measured' do
      before { span.set_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED, 1.0) }

      it 'returns true' do
        expect(described_class.eligible?(span)).to be true
      end
    end

    context 'when span has span.kind = server' do
      before { span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND, 'server') }

      it 'returns true' do
        expect(described_class.eligible?(span)).to be true
      end
    end

    context 'when span has span.kind = client' do
      before { span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND, 'client') }

      it 'returns true' do
        expect(described_class.eligible?(span)).to be true
      end
    end

    context 'when span has span.kind = producer' do
      before { span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND, 'producer') }

      it 'returns true' do
        expect(described_class.eligible?(span)).to be true
      end
    end

    context 'when span has span.kind = consumer' do
      before { span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND, 'consumer') }

      it 'returns true' do
        expect(described_class.eligible?(span)).to be true
      end
    end

    context 'when span has span.kind = internal' do
      before { span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND, 'internal') }

      it 'returns false (internal is not an eligible kind)' do
        expect(described_class.eligible?(span)).to be false
      end
    end

    context 'when span has no special markers' do
      it 'returns false' do
        expect(described_class.eligible?(span)).to be false
      end
    end

    context 'when span is both top-level and measured' do
      before do
        span.set_metric(Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL, 1.0)
        span.set_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED, 1.0)
      end

      it 'returns true' do
        expect(described_class.eligible?(span)).to be true
      end
    end
  end

  describe '.top_level?' do
    it 'returns true when _dd.top_level is 1.0' do
      span.set_metric(Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL, 1.0)
      expect(described_class.top_level?(span)).to be true
    end

    it 'returns false when _dd.top_level is not set' do
      expect(described_class.top_level?(span)).to be false
    end

    it 'returns false when _dd.top_level is 0.0' do
      span.set_metric(Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL, 0.0)
      expect(described_class.top_level?(span)).to be false
    end
  end

  describe '.measured?' do
    it 'returns true when _dd.measured is 1.0' do
      span.set_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED, 1.0)
      expect(described_class.measured?(span)).to be true
    end

    it 'returns false when _dd.measured is not set' do
      expect(described_class.measured?(span)).to be false
    end
  end
end
