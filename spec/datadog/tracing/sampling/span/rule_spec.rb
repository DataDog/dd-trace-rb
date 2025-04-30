require 'datadog/tracing/sampling/span/matcher'
require 'datadog/tracing/sampling/span/rule'

RSpec.describe Datadog::Tracing::Sampling::Span::Rule do
  subject(:rule) { described_class.new(matcher, sample_rate: sample_rate, rate_limit: rate_limit) }
  let(:matcher) { instance_double(Datadog::Tracing::Sampling::Span::Matcher) }
  let(:sample_rate) { 0.0 }
  let(:rate_limit) { 0 }

  let(:span_op) { Datadog::Tracing::SpanOperation.new(span_name, service: span_service) }
  let(:trace_op) { Datadog::Tracing::TraceOperation.new }
  let(:span_name) { 'operation.name' }
  let(:span_service) { '' }

  describe '#initialize' do
    subject(:rule) { described_class.new(matcher) }
    context 'default values' do
      it 'sets sampling rate to 100%' do
        expect(rule.sample_rate).to eq(1.0)
      end

      it 'sets rate limit unlimited' do
        expect(rule.rate_limit).to eq(-1)
      end
    end
  end

  describe '#sample!' do
    subject(:sample!) { rule.sample!(trace_op, span_op) }

    shared_examples 'does not modify span' do
      it { expect { sample! }.to_not(change { span_op.send(:build_span).to_hash }) }
    end

    context 'when matching' do
      before do
        expect(matcher).to receive(:match?).with(span_op).and_return(true)
      end

      context 'not sampled' do
        let(:sample_rate) { 0.0 }

        it 'returns rejected' do
          is_expected.to eq(:rejected)
        end

        it_behaves_like 'does not modify span'
      end

      context 'sampled' do
        let(:sample_rate) { 1.0 }

        context 'rate limited' do
          let(:rate_limit) { 0 }

          it 'returns rejected' do
            is_expected.to eq(:rejected)
          end

          it_behaves_like 'does not modify span'
        end

        context 'not rate limited' do
          let(:rate_limit) { 3 }

          it 'returns kept' do
            is_expected.to eq(:kept)
          end

          it 'sets mechanism, rule rate and rate limit metrics' do
            sample!

            expect(span_op.get_metric('_dd.span_sampling.mechanism')).to eq(8)
            expect(span_op.get_metric('_dd.span_sampling.rule_rate')).to eq(1.0)
            expect(span_op.get_metric('_dd.span_sampling.max_per_second')).to eq(3)
          end
        end
      end
    end

    context 'when not matching' do
      before do
        expect(matcher).to receive(:match?).with(span_op).and_return(false)
      end

      it 'returns nil' do
        is_expected.to eq(:not_matched)
      end

      it_behaves_like 'does not modify span'
    end
  end
end
