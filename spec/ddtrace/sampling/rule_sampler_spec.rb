require 'spec_helper'

require 'ddtrace/sampling/rule_sampler'
require 'ddtrace/sampling/rule'
require 'ddtrace/sampling/token_bucket'

RSpec.describe Datadog::Sampling::RuleSampler do
  let(:rule_sampler) { described_class.new(rules, rate_limiter, priority_sampler) }
  let(:rules) { [] }
  let(:rate_limiter) { instance_double(Datadog::Sampling::RateLimiter) }
  let(:priority_sampler) { instance_double(Datadog::RateByServiceSampler) }
  let(:effective_rate) { 0.9 }
  let(:allow?) { true }

  let(:span) { Datadog::Span.new(nil, 'dummy') }

  before do
    allow(priority_sampler).to receive(:sample?).with(span).and_return(nil)
    allow(rate_limiter).to receive(:effective_rate).and_return(effective_rate)
    allow(rate_limiter).to receive(:allow?).with(1).and_return(allow?)
  end

  shared_context 'matching rule' do
    let(:rules) { [rule] }
    let(:rule) { instance_double(Datadog::Sampling::Rule) }
    let(:response) { [sampled, sample_rate] }
    let(:sample_rate) { 0.8 }

    before do
      allow(rule).to receive(:sample).with(span).and_return(response)
    end
  end

  shared_examples 'a sampled? span' do
    it { is_expected.to eq(expected_sampled) }
  end

  describe '#sample?' do
    subject(:sample) { rule_sampler.sample?(span) }

    context 'with matching rule' do
      include_context 'matching rule'

      context 'and sampled' do
        let(:sampled) { true }

        context 'and not rate limited' do
          let(:allow?) { true }

          it_behaves_like 'a sampled? span' do
            let(:expected_sampled) { true }
          end
        end

        context 'and rate limited' do
          let(:allow?) { false }

          it_behaves_like 'a sampled? span' do
            let(:expected_sampled) { false }
          end
        end

        context 'with many rules' do
          let(:rules) { [non_matching_rule, rule, late_matching_rule] }
          let(:non_matching_rule) { instance_double(Datadog::Sampling::Rule) }
          let(:late_matching_rule) { instance_double(Datadog::Sampling::Rule) }

          before do
            allow(non_matching_rule).to receive(:sample).and_return(nil)
            allow(late_matching_rule).to receive(:sample).and_return([!sampled, 0.0])
          end

          it 'matches first matching rule' do
            is_expected.to eq(sampled)

            expect(non_matching_rule).to have_received(:sample)
            expect(late_matching_rule).to_not have_received(:sample)
          end
        end
      end

      context 'and not sampled' do
        let(:sampled) { false }

        it_behaves_like 'a sampled? span' do
          let(:expected_sampled) { false }
        end
      end
    end

    context 'with no matching rule' do
      let(:delegated) { double }

      before do
        allow(priority_sampler).to receive(:sample?).with(span).and_return(delegated)
      end

      it { is_expected.to eq(delegated) }
    end
  end

  describe '#sample!' do
    subject(:sample) { rule_sampler.sample!(span) }

    shared_examples 'a sampled! span' do
      it_behaves_like 'a sampled? span'

      before { subject }

      it 'sets `span.sampled` flag' do
        expect(span.sampled).to eq(expected_sampled)
      end

      it 'sets metrics' do
        expect(span.get_metric(Datadog::Ext::Sampling::RULE_SAMPLE_RATE)).to eq(sample_rate)
        expect(span.get_metric(Datadog::Ext::Sampling::RATE_LIMITER_RATE)).to eq(effective_rate)
      end
    end

    context 'with matching rule' do
      include_context 'matching rule'

      context 'and sampled' do
        let(:sampled) { true }

        context 'and not rate limited' do
          let(:allow?) { true }

          it_behaves_like 'a sampled! span' do
            let(:expected_sampled) { true }
          end
        end

        context 'and rate limited' do
          let(:allow?) { false }

          it_behaves_like 'a sampled! span' do
            let(:expected_sampled) { false }
          end
        end
      end

      context 'and not sampled' do
        let(:sampled) { false }

        it_behaves_like 'a sampled! span' do
          let(:expected_sampled) { false }
        end
      end
    end

    context 'with no matching rule' do
      let(:delegated) { double }

      before do
        allow(priority_sampler).to receive(:sample!).with(span).and_return(delegated)
      end

      it { is_expected.to eq(delegated) }

      it 'skips metrics' do
        expect(span.get_metric(Datadog::Ext::Sampling::RULE_SAMPLE_RATE)).to be_nil
        expect(span.get_metric(Datadog::Ext::Sampling::RATE_LIMITER_RATE)).to be_nil
      end
    end
  end
end
