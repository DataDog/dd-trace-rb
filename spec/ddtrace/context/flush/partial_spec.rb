require 'spec_helper'

require 'ddtrace/context'
require_relative 'shared_examples'

RSpec.describe Datadog::Context::Flush::Partial do
  subject(:context_flush) { described_class.new(min_spans_before_partial_flush: min_spans_for_partial) }
  let(:min_spans_for_partial) { 2 }

  describe '#consume' do
    subject(:consume) { context_flush.consume(context) }

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
        let(:finished_spans) { [double, double] }

        before do
          allow(context).to receive(:delete_span_if) do |&block|
            expect(block).to eq(:finished?.to_proc)
            finished_spans
          end

          allow(context).to receive(:configure_root_span).with(finished_spans[0])
        end

        it 'returns finished spans' do
          is_expected.to eq(finished_spans)
        end

        it 'apply root span settings to first span' do
          subject
          expect(context).to have_received(:configure_root_span).with(finished_spans[0])
        end
      end
    end
  end
end
