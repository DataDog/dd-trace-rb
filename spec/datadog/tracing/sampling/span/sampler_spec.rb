require 'datadog/tracing/sampling/span/matcher'
require 'datadog/tracing/sampling/span/rule'

require 'datadog/tracing/sampling/span/sampler'

RSpec.describe Datadog::Tracing::Sampling::Span::Sampler do
  subject(:sampler) { described_class.new(rules) }
  let(:rules) { [] }

  let(:trace_op) { Datadog::Tracing::TraceOperation.new }
  let(:span_op) { Datadog::Tracing::SpanOperation.new('name', service: 'service') }

  describe '#sample!' do
    subject(:sample!) { sampler.sample!(trace_op, span_op) }

    shared_examples 'does not modify trace' do
      it 'does not change span' do
        expect { sample! }.to_not(change { span_op.send(:build_span).to_hash })
      end

      it 'does not change sampling decision' do
        expect { sample! }.to_not(
          change do
            trace_op.get_tag(
              Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER
            )
          end
        )
      end
    end

    shared_examples 'set sampling decision' do
      it do
        sample!
        expect(span_op.get_metric('_dd.span_sampling.mechanism')).to_not be_nil
        expect(trace_op.get_tag('_dd.p.dm')).to eq('-8')
      end
    end

    let(:match_all) { Datadog::Tracing::Sampling::Span::Matcher.new }

    context 'no matching rules' do
      it_behaves_like 'does not modify trace'
    end

    context 'with matching rules' do
      let(:rules) { [Datadog::Tracing::Sampling::Span::Rule.new(match_all, sample_rate: 1.0, rate_limit: 3)] }

      context 'a kept trace' do
        before { trace_op.keep! }

        it_behaves_like 'does not modify trace'
      end

      context 'a rejected trace' do
        before { trace_op.reject! }

        it_behaves_like 'set sampling decision' do
          let(:decision_carrier) { span_op }
        end

        context 'multiple rules' do
          let(:rules) do
            [
              Datadog::Tracing::Sampling::Span::Rule.new(match_all, sample_rate: 1.0, rate_limit: 3),
              Datadog::Tracing::Sampling::Span::Rule.new(match_all, sample_rate: 0.5, rate_limit: 2),
            ]
          end

          it 'applies the first matching rule' do
            sample!

            expect(span_op.get_metric('_dd.span_sampling.rule_rate')).to eq(1.0)
            expect(span_op.get_metric('_dd.span_sampling.max_per_second')).to eq(3)
            expect(trace_op.get_tag('_dd.p.dm')).to eq('-8')
          end
        end
      end

      context 'a trace rejected by priority sampling only' do
        before do
          trace_op.keep!
          trace_op.sampling_priority = Datadog::Tracing::Sampling::Ext::Priority::AUTO_REJECT
        end

        it_behaves_like 'set sampling decision' do
          let(:decision_carrier) { trace_op }
        end
      end

      context 'that rejects spans' do
        let(:rules) { [Datadog::Tracing::Sampling::Span::Rule.new(match_all, sample_rate: 0.0, rate_limit: 0)] }

        it_behaves_like 'does not modify trace'
      end
    end
  end
end
