# typed: ignore

require 'datadog/tracing/contrib/propagation/sql_comment'

RSpec.describe Datadog::Tracing::Contrib::Propagation::SqlComment do
  let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new(mode) }
  let(:span_op) { Datadog::Tracing::SpanOperation.new('sql_comment_propagation_span') }

  describe '.annotate!' do
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
    around do |example|
      without_warnings { Datadog.configuration.reset! }
      example.run
      without_warnings { Datadog.configuration.reset! }
    end

    before do
      Datadog.configure do |c|
        c.env = 'production'
        c.service = "Traders' Joe"
        c.version = '1.0.0'
      end
    end

    let(:sql_statement) { 'SELECT 1' }

    subject { described_class.prepend_comment(sql_statement, span_op, propagation_mode) }

    context 'when `disabled` mode' do
      let(:mode) { 'disabled' }

      it { is_expected.to eq(sql_statement) }
    end

    context 'when `service` mode' do
      let(:mode) { 'service' }

      it { is_expected.to eq("/*dde='production',ddps='Traders%27%20Joe',ddpv='1.0.0'*/ #{sql_statement}") }
    end

    xcontext 'when `full` mode' do
      let(:mode) { 'full' }

      it { is_expected.to eq(sql_statement) }
    end
  end
end
