# typed: ignore

require 'datadog/tracing/contrib/propagation/sql_comment'

RSpec.describe Datadog::Tracing::Contrib::Propagation::SqlComment do
  describe '.annotate!' do
    let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new(mode) }
    let(:span_op) { Datadog::Tracing::SpanOperation.new('sql_comment_propagation_span') }

    context 'when `disabled` mode' do
      let(:mode) { 'disabled' }

      it do
        described_class.annotate!(span_op, propagation_mode)

        expect(span_op.get_tag('_dd.dbm_trace_injected')).to be_nil
      end
    end

    context 'when `service` mode' do
      let(:mode) { 'service' }

      it do
        described_class.annotate!(span_op, propagation_mode)

        expect(span_op.get_tag('_dd.dbm_trace_injected')).to be_nil
      end
    end

    context 'when `full` mode' do
      let(:mode) { 'full' }

      it do
        described_class.annotate!(span_op, propagation_mode)

        expect(span_op.get_tag('_dd.dbm_trace_injected')).to eq('true')
      end
    end

  end

  describe '.prepend_comment' do
  end
end
