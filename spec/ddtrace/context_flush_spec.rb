require 'spec_helper'

require 'ddtrace/context_flush'

RSpec.shared_context 'trace context' do
  let(:context) { instance_double(Datadog::Context, get: get) }

  let(:get) { [trace, sampled] }
  let(:sampled) { true }
  let(:trace) { [double] }
end

RSpec.shared_examples_for 'a context flusher' do
  context 'with request not sampled' do
    let(:sampled) { false }

    it 'returns nil' do
      is_expected.to be_nil
    end
  end

  context 'with request sampled' do
    let(:sampled) { true }

    it 'returns the original trace' do
      is_expected.to eq(trace)
    end
  end
end

RSpec.describe Datadog::ContextFlush::Finished do
  subject(:context_flush) { described_class.new }

  describe '#consume' do
    subject(:consume) { context_flush.consume!(context) }

    include_context 'trace context'
    it_behaves_like 'a context flusher'
  end
end

RSpec.describe Datadog::ContextFlush::Partial do
  subject(:context_flush) { described_class.new(min_spans_before_partial_flush: min_spans_for_partial) }
  let(:min_spans_for_partial) { 2 }

  describe '#consume' do
    subject(:consume) { context_flush.consume!(context) }

    include_context 'trace context'
    it_behaves_like 'a context flusher'

    context 'with empty trace' do
      let(:trace) { [] }

      let(:finished_span_count) { finished_spans.size }

      before { allow(context).to receive(:finished_span_count).and_return(finished_span_count) }

      context 'with fewer than the minimum required spans' do
        let(:finished_spans) { [double] }

        it { is_expected.to be_nil }
      end

      context 'with at least the minimum required spans' do
        context 'with spans available' do
          let(:finished_spans) { [double, double] }

          before do
            allow(context).to receive(:delete_span_if) do |&block|
              # Assert correct block is passed in
              block.call(spy = spy())
              expect(spy).to have_received(:finished?)

              finished_spans
            end

            allow(context).to receive(:annotate_for_flush!).with(finished_spans[0])
          end

          it 'returns finished spans' do
            is_expected.to eq(finished_spans)
          end

          it 'apply root span settings to first span' do
            subject
            expect(context).to have_received(:annotate_for_flush!).with(finished_spans[0])
          end
        end

        context 'with no span available due to race condition' do
          # Can happen if between the call to +context.finished_span_count+
          # and +context.delete_span_if+ all finished spans are consumed.

          let(:finished_spans) { [] }
          before { allow(context).to receive(:delete_span_if).and_return(finished_spans) }

          it 'returns finished spans' do
            is_expected.to be_nil
          end
        end
      end
    end
  end
end
