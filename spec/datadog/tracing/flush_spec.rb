# typed: false
require 'spec_helper'

require 'datadog/tracing/flush'
require 'datadog/tracing/trace_operation'
require 'datadog/tracing/trace_segment'

RSpec.shared_context 'trace operation' do
  let(:trace_op) do
    instance_double(
      Datadog::Tracing::TraceOperation,
      sampled?: sampled,
      finished?: finished,
      flush!: trace
    )
  end

  let(:sampled) { true }
  let(:finished) { true }
  let(:trace) { instance_double(Datadog::Tracing::TraceSegment) }
end

RSpec.shared_examples_for 'a trace flusher' do
  context 'given a finished trace operation' do
    let(:finished) { true }

    context 'that is not sampled' do
      let(:sampled) { false }
      it { is_expected.to be nil }
    end

    context 'that is sampled' do
      let(:sampled) { true }
      it { is_expected.to eq(trace) }
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

      context 'that is not sampled' do
        let(:sampled) { false }
        it { is_expected.to be nil }
      end

      context 'that is sampled' do
        let(:sampled) { true }
        it { is_expected.to be nil }
      end
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

      context 'that is not sampled' do
        let(:sampled) { false }
        it { is_expected.to be nil }
      end

      context 'that is sampled' do
        let(:sampled) { true }

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
end
