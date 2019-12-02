require 'spec_helper'

require 'ddtrace/sampling/rule_sampler'
require 'ddtrace/sampling/rule'
require 'ddtrace/sampling/rate_limiter'

RSpec.describe Datadog::Sampling::RuleSampler do
  let(:rule_sampler) { described_class.new(rules, rate_limiter: rate_limiter, default_sampler: default_sampler) }
  let(:rules) { [] }
  let(:rate_limiter) { instance_double(Datadog::Sampling::RateLimiter) }
  let(:default_sampler) { instance_double(Datadog::RateByServiceSampler) }
  let(:effective_rate) { 0.9 }
  let(:allow?) { true }

  let(:span) { Datadog::Span.new(nil, 'dummy') }

  before do
    allow(default_sampler).to receive(:sample?).with(span).and_return(nil)
    allow(rate_limiter).to receive(:effective_rate).and_return(effective_rate)
    allow(rate_limiter).to receive(:allow?).with(1).and_return(allow?)
  end

  context '#initialize' do
    subject(:rule_sampler) { described_class.new(rules) }

    it { expect(subject.rate_limiter).to be_a(Datadog::Sampling::UnlimitedLimiter) }
    it { expect(subject.default_sampler).to be_a(Datadog::AllSampler) }

    context 'with rate_limit' do
      subject(:rule_sampler) { described_class.new(rules, rate_limit: 1.0) }

      it { expect(subject.rate_limiter).to be_a(Datadog::Sampling::TokenBucket) }
    end

    context 'with default_sample_rate' do
      subject(:rule_sampler) { described_class.new(rules, default_sample_rate: 1.0) }

      it { expect(subject.default_sampler).to be_a(Datadog::RateSampler) }
    end
  end

  shared_context 'matching rule' do
    let(:rules) { [rule] }
    let(:rule) { instance_double(Datadog::Sampling::Rule) }
    let(:sample_rate) { 0.8 }

    before do
      allow(rule).to receive(:match?).with(span).and_return(true)
      allow(rule).to receive(:sample?).with(span).and_return(sampled)
      allow(rule).to receive(:sample_rate).with(span).and_return(sample_rate)
    end
  end

  describe '#sample!' do
    subject(:sample) { rule_sampler.sample!(span) }

    shared_examples 'a sampled! span' do
      before { subject }

      it { is_expected.to eq(expected_sampled) }

      it 'sets `span.sampled` flag' do
        expect(span.sampled).to eq(expected_sampled)
      end

      it 'sets rule metrics' do
        expect(span.get_metric(Datadog::Ext::Sampling::RULE_SAMPLE_RATE)).to eq(sample_rate)
      end

      it 'sets limiter metrics' do
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
          let(:effective_rate) { nil } # Rate limiter was not evaluated
        end
      end
    end

    context 'with no matching rule' do
      let(:delegated) { double }

      before do
        allow(default_sampler).to receive(:sample!).with(span).and_return(delegated)
      end

      it { is_expected.to eq(delegated) }

      it 'skips metrics' do
        expect(span.get_metric(Datadog::Ext::Sampling::RULE_SAMPLE_RATE)).to be_nil
        expect(span.get_metric(Datadog::Ext::Sampling::RATE_LIMITER_RATE)).to be_nil
      end
    end
  end

  describe '#sample?' do
    subject(:sample) { rule_sampler.sample?(span) }

    it { expect { subject }.to raise_error(StandardError, 'RuleSampler cannot be evaluated without side-effects') }
  end
end
