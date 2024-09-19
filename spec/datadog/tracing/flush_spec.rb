require 'spec_helper'

require 'datadog/tracing/flush'
require 'datadog/tracing/trace_operation'
require 'datadog/tracing/trace_segment'

RSpec.shared_context 'trace operation' do
  let(:trace_op) do
    instance_double(
      Datadog::Tracing::TraceOperation,
      finished?: finished,
      flush!: trace
    )
  end

  let(:finished) { true }
  let(:trace) { instance_double(Datadog::Tracing::TraceSegment) }
end

RSpec.shared_examples_for 'a trace flusher' do
  context 'given a finished trace operation' do
    let(:finished) { true }

    it { is_expected.to eq(trace) }
  end

  context 'with a single sampled span' do
    let(:trace_op) { Datadog::Tracing::TraceOperation.new(sampled: sampled) }

    before do
      trace_op.measure('single.sampled') do |span|
        span.set_metric(Datadog::Tracing::Sampling::Span::Ext::TAG_MECHANISM, 8)

        trace_op.measure('not_single.sampled') {}
      end
    end

    context 'and a kept trace' do
      let(:sampled) { true }

      it 'returns all spans' do
        is_expected.to have_attributes(spans: have(2).items)
      end
    end

    context 'and a rejected trace' do
      let(:sampled) { false }

      it 'returns only single sampled spans' do
        is_expected.to have_attributes(spans: [have_attributes(name: 'single.sampled')])
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Flush::Finished do
  subject(:trace_flush) { described_class.new }

  describe '#consume' do
    subject(:consume) { trace_flush.consume!(trace_op) }

    include_context 'trace operation'
    it_behaves_like 'a trace flusher'

    context 'with partially completed trace operation' do
      let(:finished) { false }
      it { is_expected.to be nil }
    end
  end
end

RSpec.describe Datadog::Tracing::Flush::Partial do
  subject(:trace_flush) { described_class.new(min_spans_before_partial_flush: min_spans_for_partial) }

  let(:min_spans_for_partial) { 2 }

  describe '#consume' do
    subject(:consume) { trace_flush.consume!(trace_op) }

    include_context 'trace operation'
    it_behaves_like 'a trace flusher'

    context 'with partially completed trace operation' do
      let(:finished) { false }

      before do
        allow(trace_op).to receive(:finished_span_count).and_return(finished_span_count)
      end

      context 'containing fewer than the minimum required spans' do
        let(:finished_span_count) { min_spans_for_partial - 1 }
        it { is_expected.to be nil }
      end

      context 'containing at least the minimum required spans' do
        let(:finished_span_count) { min_spans_for_partial }
        it { is_expected.to eq(trace) }
      end
    end
  end
end
