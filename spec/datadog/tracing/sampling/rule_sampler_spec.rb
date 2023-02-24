require 'spec_helper'

require 'datadog/tracing'
require 'datadog/tracing/sampling/rate_by_service_sampler'
require 'datadog/tracing/sampling/rate_limiter'
require 'datadog/tracing/sampling/rule_sampler'
require 'datadog/tracing/sampling/rule'

RSpec.describe Datadog::Tracing::Sampling::RuleSampler do
  let(:rule_sampler) { described_class.new(rules, rate_limiter: rate_limiter, default_sampler: default_sampler) }
  let(:rules) { [] }
  let(:rate_limiter) { instance_double(Datadog::Tracing::Sampling::RateLimiter) }
  let(:default_sampler) { instance_double(Datadog::Tracing::Sampling::RateByServiceSampler) }
  let(:effective_rate) { 0.9 }
  let(:allow?) { true }

  let(:trace) { Datadog::Tracing::TraceOperation.new }

  before do
    allow(default_sampler).to receive(:sample?).with(trace).and_return(nil)
    allow(rate_limiter).to receive(:effective_rate).and_return(effective_rate)
    allow(rate_limiter).to receive(:allow?).with(1).and_return(allow?)
  end

  shared_examples 'a simple rule that matches all span operations' do |options = { sample_rate: 1.0 }|
    it do
      expect(rule.matcher.name).to eq(Datadog::Tracing::Sampling::SimpleMatcher::MATCH_ALL)
      expect(rule.matcher.service).to eq(Datadog::Tracing::Sampling::SimpleMatcher::MATCH_ALL)
      expect(rule.sampler.sample_rate).to eq(options[:sample_rate])
    end
  end

  describe '#initialize' do
    subject(:rule_sampler) { described_class.new(rules) }

    it { expect(rule_sampler.rate_limiter).to be_a(Datadog::Tracing::Sampling::TokenBucket) }
    it { expect(rule_sampler.default_sampler).to be_a(Datadog::Tracing::Sampling::RateByServiceSampler) }

    context 'with rate_limit ENV' do
      before do
        allow(Datadog.configuration.tracing.sampling).to receive(:rate_limit)
          .and_return(20.0)
      end

      it { expect(rule_sampler.rate_limiter).to be_a(Datadog::Tracing::Sampling::TokenBucket) }
    end

    context 'with default_sample_rate ENV' do
      before do
        allow(Datadog.configuration.tracing.sampling).to receive(:default_rate)
          .and_return(0.5)
      end

      it_behaves_like 'a simple rule that matches all span operations', sample_rate: 0.5 do
        let(:rule) { rule_sampler.rules.last }
      end
    end

    context 'with rate_limit' do
      subject(:rule_sampler) { described_class.new(rules, rate_limit: 1.0) }

      it { expect(rule_sampler.rate_limiter).to be_a(Datadog::Tracing::Sampling::TokenBucket) }
    end

    context 'with nil rate_limit' do
      subject(:rule_sampler) { described_class.new(rules, rate_limit: nil) }

      it { expect(rule_sampler.rate_limiter).to be_a(Datadog::Tracing::Sampling::UnlimitedLimiter) }
    end

    context 'with default_sample_rate' do
      subject(:rule_sampler) { described_class.new(rules, default_sample_rate: 1.0) }

      it_behaves_like 'a simple rule that matches all span operations', sample_rate: 1.0 do
        let(:rule) { rule_sampler.rules.last }
      end
    end
  end

  shared_context 'matching rule' do
    let(:rules) { [rule] }
    let(:rule) { instance_double(Datadog::Tracing::Sampling::Rule) }
    let(:sample_rate) { 0.8 }

    before do
      allow(rule).to receive(:match?).with(trace).and_return(true)
      allow(rule).to receive(:sample?).with(trace).and_return(sampled)
      allow(rule).to receive(:sample_rate).with(trace).and_return(sample_rate)
    end
  end

  describe '#sample!' do
    subject(:sample) { rule_sampler.sample!(trace) }

    shared_examples 'a sampled! trace' do
      before { subject }

      let(:sampling_decision) { defined?(super) ? super() : '-3' }

      it { is_expected.to eq(expected_sampled) }

      it 'sets `trace.sampled?` flag' do
        expect(trace.sampled?).to eq(expected_sampled)
      end

      it 'sets rule metrics' do
        expect(trace.rule_sample_rate).to eq(sample_rate)
      end

      it 'sets limiter metrics' do
        expect(trace.rate_limiter_rate).to eq(effective_rate)
      end

      it 'sets the sampling priority' do
        expect(trace.sampling_priority).to eq(sampling_priority)
      end

      it 'sets the sampling decision' do
        expect(trace.get_tag('_dd.p.dm')).to eq(sampling_decision)
      end
    end

    context 'with matching rule' do
      include_context 'matching rule'

      context 'and sampled' do
        let(:sampled) { true }

        context 'and not rate limited' do
          let(:allow?) { true }

          it_behaves_like 'a sampled! trace' do
            let(:expected_sampled) { true }
            let(:sampling_priority) { 2 }
          end
        end

        context 'and rate limited' do
          let(:allow?) { false }

          it_behaves_like 'a sampled! trace' do
            let(:expected_sampled) { false }
            let(:sampling_priority) { -1 }
          end
        end
      end

      context 'and not sampled' do
        let(:sampled) { false }

        it_behaves_like 'a sampled! trace' do
          let(:expected_sampled) { false }
          let(:sampling_priority) { -1 }
          let(:sampling_decision) { nil }
          let(:effective_rate) { nil } # Rate limiter was not evaluated
        end
      end
    end

    context 'with no matching rule' do
      let(:delegated) { double }

      before do
        allow(default_sampler).to receive(:sample!).with(trace).and_return(delegated)
      end

      it { is_expected.to eq(delegated) }

      it 'skips metrics' do
        sample
        expect(trace.rule_sample_rate).to be_nil
        expect(trace.rate_limiter_rate).to be_nil
        expect(trace.sampling_priority).to be_nil
      end

      it 'does not set sampling priority' do
        sample
        expect(trace.sampling_priority).to be_nil
      end

      context 'when the default sampler is a RateByServiceSampler' do
        let(:default_sampler) { Datadog::Tracing::Sampling::RateByServiceSampler.new }
        let(:sample_rate) { rand }

        it 'sets the agent rate metric' do
          expect(default_sampler).to receive(:sample_rate)
            .with(trace)
            .and_return(sample_rate)
          sample
          expect(trace.agent_sample_rate).to eq(sample_rate)
        end
      end
    end
  end

  describe '#sample?' do
    subject(:sample?) { rule_sampler.sample?(trace) }

    it { expect { sample? }.to raise_error(StandardError, 'RuleSampler cannot be evaluated without side-effects') }
  end

  describe '#update' do
    subject(:update) { rule_sampler.update(rates, decision: decision) }

    let(:rates) { { 'service:my-service,env:test' => rand } }
    let(:decision) { 'test decision' }

    context 'when configured with a default sampler' do
      context 'that responds to #update' do
        let(:default_sampler) { sampler_class.new }
        let(:sampler_class) do
          stub_const(
            'TestSampler',
            Class.new(Datadog::Tracing::Sampling::Sampler) do
              def update(rates, decision: nil)
                [rates, decision]
              end
            end
          )
        end

        before do
          allow(default_sampler).to receive(:update)
          update
        end

        it 'forwards to the default sampler' do
          expect(default_sampler).to have_received(:update)
            .with(rates, decision: decision)
        end
      end

      context 'that does not respond to #update' do
        let(:default_sampler) { sampler_class.new }
        let(:sampler_class) do
          stub_const('TestSampler', Class.new(Datadog::Tracing::Sampling::Sampler))
        end

        it 'does not forward to the default sampler' do
          expect { update }.to_not raise_error
          is_expected.to be false
        end
      end
    end
  end
end
