# typed: false
require 'datadog/ci/spec_helper'

require 'ddtrace/trace_segment'
require 'ddtrace/trace_operation'
require 'datadog/ci/trace_flush'

RSpec.shared_context 'CI trace operation' do
  let(:trace_op) do
    instance_double(
      Datadog::TraceOperation,
      origin: origin,
      sampled?: sampled,
      finished?: finished,
      flush!: trace
    )
  end

  let(:origin) { 'ci-origin' }
  let(:sampled) { true }
  let(:finished) { true }

  let(:trace) { Datadog::TraceSegment.new(spans, origin: origin) }
  let(:spans) { Array.new(3) { |i| Datadog::Span.new("span #{i}") } }
end

RSpec.shared_examples_for 'a CI trace flusher' do
  context 'given a finished trace operation' do
    let(:finished) { true }

    context 'that is not sampled' do
      let(:sampled) { false }
      it { is_expected.to be nil }
    end

    context 'that is sampled' do
      let(:sampled) { true }
      it { is_expected.to eq(trace) }

      it 'tags every span with the origin' do
        is_expected.to eq(trace)

        # Expect each span to have an attached origin
        trace.spans.each do |span|
          expect(span.get_tag(Datadog::Ext::DistributedTracing::TAG_ORIGIN))
            .to eq(trace.origin)
        end
      end
    end
  end
end

RSpec.describe Datadog::CI::TraceFlush::Finished do
  subject(:trace_flush) { described_class.new }

  describe '#consume' do
    subject(:consume) { trace_flush.consume!(trace_op) }

    include_context 'CI trace operation'
    it_behaves_like 'a CI trace flusher'
  end
end

RSpec.describe Datadog::CI::TraceFlush::Partial do
  subject(:trace_flush) { described_class.new(min_spans_before_partial_flush: min_spans_for_partial) }

  let(:min_spans_for_partial) { 2 }

  describe '#consume' do
    subject(:consume) { trace_flush.consume!(trace_op) }

    include_context 'CI trace operation'
    it_behaves_like 'a CI trace flusher'
  end
end
