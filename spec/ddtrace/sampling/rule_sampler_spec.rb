# typed: false
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

  let(:span) { Datadog::SpanOperation.new('dummy') }

  before do
    allow(default_sampler).to receive(:sample?).with(span).and_return(nil)
    allow(rate_limiter).to receive(:effective_rate).and_return(effective_rate)
    allow(rate_limiter).to receive(:allow?).with(1).and_return(allow?)
  end

  shared_examples 'a simple rule that matches all spans' do |options = { sample_rate: 1.0 }|
    it do
      expect(rule.matcher.name).to eq(Datadog::Sampling::SimpleMatcher::MATCH_ALL)
      expect(rule.matcher.service).to eq(Datadog::Sampling::SimpleMatcher::MATCH_ALL)
      expect(rule.sampler.sample_rate).to eq(options[:sample_rate])
    end
  end

  describe '#initialize' do
    subject(:rule_sampler) { described_class.new(rules) }

    it { expect(rule_sampler.rate_limiter).to be_a(Datadog::Sampling::TokenBucket) }
    it { expect(rule_sampler.default_sampler).to be_a(Datadog::RateByServiceSampler) }

    context 'with rate_limit ENV' do
      before do
        allow(Datadog.configuration.sampling).to receive(:rate_limit)
          .and_return(20.0)
      end

      it { expect(rule_sampler.rate_limiter).to be_a(Datadog::Sampling::TokenBucket) }
    end

    context 'with default_sample_rate ENV' do
      before do
        allow(Datadog.configuration.sampling).to receive(:default_rate)
          .and_return(0.5)
      end

      it_behaves_like 'a simple rule that matches all spans', sample_rate: 0.5 do
        let(:rule) { rule_sampler.rules.last }
      end
    end

    context 'with rate_limit' do
      subject(:rule_sampler) { described_class.new(rules, rate_limit: 1.0) }

      it { expect(rule_sampler.rate_limiter).to be_a(Datadog::Sampling::TokenBucket) }
    end

    context 'with nil rate_limit' do
      subject(:rule_sampler) { described_class.new(rules, rate_limit: nil) }

      it { expect(rule_sampler.rate_limiter).to be_a(Datadog::Sampling::UnlimitedLimiter) }
    end

    context 'with default_sample_rate' do
      subject(:rule_sampler) { described_class.new(rules, default_sample_rate: 1.0) }

      it_behaves_like 'a simple rule that matches all spans', sample_rate: 1.0 do
        let(:rule) { rule_sampler.rules.last }
      end
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

      context 'when the default sampler is a RateByServiceSampler' do
        let(:default_sampler) { Datadog::RateByServiceSampler.new }
        let(:sample_rate) { rand }

        it 'sets the agent rate metric' do
          expect(default_sampler).to receive(:sample_rate)
            .with(span)
            .and_return(sample_rate)
          sample
          expect(span.get_metric(described_class::AGENT_RATE_METRIC_KEY)).to eq(sample_rate)
        end
      end
    end
  end

  describe '#sample?' do
    subject(:sample) { rule_sampler.sample?(span) }

    it { expect { subject }.to raise_error(StandardError, 'RuleSampler cannot be evaluated without side-effects') }
  end

  describe '#update' do
    subject(:update) { rule_sampler.update(rates) }

    let(:rates) { { 'service:my-service,env:test' => rand } }

    context 'when configured with a default sampler' do
      context 'that responds to #update' do
        let(:default_sampler) { sampler_class.new }
        let(:sampler_class) do
          stub_const('TestSampler', Class.new(Datadog::Sampler) do
            def update(rates)
              rates
            end
          end)
        end

        before do
          allow(default_sampler).to receive(:update)
          update
        end

        it 'forwards to the default sampler' do
          expect(default_sampler).to have_received(:update)
            .with(rates)
        end
      end

      context 'that does not respond to #update' do
        let(:default_sampler) { sampler_class.new }
        let(:sampler_class) do
          stub_const('TestSampler', Class.new(Datadog::Sampler))
        end

        it 'does not forward to the default sampler' do
          expect { update }.to_not raise_error
          is_expected.to be false
        end
      end
    end
  end
end
