require 'spec_helper'

require 'logger'

require 'datadog/core'
require 'datadog/tracing/sampling/ext'
require 'datadog/tracing/sampling/priority_sampler'
require 'datadog/tracing/sampling/rate_by_service_sampler'
require 'datadog/tracing/sampling/rate_sampler'
require 'datadog/tracing/sampling/rule_sampler'
require 'datadog/tracing/trace_operation'

RSpec.describe Datadog::Tracing::Sampling::PrioritySampler do
  subject(:sampler) { described_class.new(base_sampler: base_sampler, post_sampler: post_sampler) }

  let(:base_sampler) { nil }
  let(:post_sampler) { nil }

  let(:sample_rate_tag_value) { nil }

  before { Datadog.logger.level = Logger::FATAL }

  after { Datadog.logger.level = Logger::WARN }

  describe '#sample!' do
    subject(:sample) { sampler.sample!(trace) }
    let(:keep_priority) { Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP }
    let(:drop_priority) { Datadog::Tracing::Sampling::Ext::Priority::AUTO_REJECT }
    let(:sampling_priority) { keep_priority }

    shared_examples_for 'priority sampling' do
      let(:trace) { Datadog::Tracing::TraceOperation.new(id: 1) }
      let(:decision) { defined?(super) ? super() : '-1' }

      context 'by default' do
        it do
          expect(sample).to be true
          expect(trace.sampled?).to be(true)
          expect(trace.get_tag('_dd.p.dm')).to eq(decision)
        end
      end

      context 'but no sampling priority' do
        it do
          expect(sample).to be true
          expect(trace.sampling_priority).to be(sampling_priority)
          expect(trace.sampled?).to be(true)
          expect(trace.sample_rate).to eq(sample_rate_tag_value)
          expect(trace.get_tag('_dd.p.dm')).to eq(decision)
        end
      end

      context 'and USER_KEEP sampling priority' do
        before { trace.sampling_priority = Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP }

        it do
          expect(sample).to be true
          expect(trace.sampling_priority).to be(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)
          expect(trace.sampled?).to be(true)
          expect(trace.sample_rate).to eq(sample_rate_tag_value)
          expect(trace.get_tag('_dd.p.dm')).to be(nil)
        end
      end

      context 'and AUTO_KEEP sampling priority' do
        before { trace.sampling_priority = Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP }

        it do
          expect(sample).to be true
          expect(trace.sampling_priority).to be(Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP)
          expect(trace.sampled?).to be(true)
          expect(trace.sample_rate).to eq(sample_rate_tag_value)
          expect(trace.get_tag('_dd.p.dm')).to be(nil)
        end
      end

      context 'and AUTO_REJECT sampling priority' do
        before { trace.sampling_priority = Datadog::Tracing::Sampling::Ext::Priority::AUTO_REJECT }

        it do
          expect(sample).to be true
          expect(trace.sampling_priority).to be(Datadog::Tracing::Sampling::Ext::Priority::AUTO_REJECT)
          expect(trace.sampled?).to be(true) # Priority sampling always samples
          expect(trace.sample_rate).to eq(sample_rate_tag_value)
          expect(trace.get_tag('_dd.p.dm')).to be(nil)
        end
      end

      context 'and USER_REJECT sampling priority' do
        before { trace.sampling_priority = Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT }

        it do
          expect(sample).to be true
          expect(trace.sampling_priority).to be(Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT)
          expect(trace.sampled?).to be(true) # Priority sampling always samples
          expect(trace.sample_rate).to eq(sample_rate_tag_value)
          expect(trace.get_tag('_dd.p.dm')).to be(nil)
        end
      end
    end

    shared_examples_for 'priority sampling without scaling' do
      it_behaves_like 'priority sampling' do
        # It should not set this tag; otherwise it will errantly scale up metrics.
        let(:sample_rate_tag_value) { nil }
      end
    end

    context 'when configured with defaults' do
      let(:sampler) { described_class.new }

      it_behaves_like 'priority sampling without scaling'
    end

    context 'when configured with a pre-sampler RateSampler < 1.0' do
      let(:base_sampler) { Datadog::Tracing::Sampling::RateSampler.new(sample_rate) }
      let(:sample_rate) { 0.5 }

      it_behaves_like 'priority sampling' do
        # It must set this tag; otherwise it won't scale up metrics properly.
        let(:sample_rate_tag_value) { sample_rate }
      end

      context 'with a priority-sampler that sets sampling rate metrics' do
        let(:post_sampler) { Datadog::Tracing::Sampling::RateSampler.new(1.0) }

        it_behaves_like 'priority sampling' do
          # It must set this tag; otherwise it won't scale up metrics properly.
          let(:sample_rate_tag_value) { sample_rate }
          let(:decision) { '-4' }
        end

        context 'with decision set' do
          let(:post_sampler) { Datadog::Tracing::Sampling::RateSampler.new(1.0, decision: decision) }
          let(:decision) { 'test decision' }

          it_behaves_like 'priority sampling' do
            # It must set this tag; otherwise it won't scale up metrics properly.
            let(:sample_rate_tag_value) { sample_rate }
          end
        end
      end
    end

    context 'when configured with a pre-sampler RateSampler = 1.0' do
      let(:base_sampler) { Datadog::Tracing::Sampling::RateSampler.new(sample_rate) }
      let(:sample_rate) { 1.0 }

      it_behaves_like 'priority sampling without scaling'

      context 'with a priority-sampler that sets sampling rate metrics' do
        let(:post_sampler) { Datadog::Tracing::Sampling::RateSampler.new(1.0) }
        let(:decision) { '-4' }

        it_behaves_like 'priority sampling without scaling'
      end
    end

    context 'when configured with a priority-sampler RateByServiceSampler < 1.0' do
      let(:post_sampler) { Datadog::Tracing::Sampling::RateByServiceSampler.new(sample_rate, env: env) }
      let(:sample_rate) { 0.5 }
      let(:decision) { '-0' }
      let(:env) { 'test-env' }

      it_behaves_like 'priority sampling without scaling'

      context 'with agent rates' do
        before { post_sampler.update({ 'service:,env:test-env' => 0.5 }, decision: decision) }
        let(:decision) { 'test decision' }

        it_behaves_like 'priority sampling without scaling'
      end
    end

    context 'when configured with a priority-sampler RuleSampler' do
      let(:keep_priority) {  Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP }
      let(:drop_priority) {  Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT }
      let(:decision) { '-3' }

      context 'that keeps the trace' do
        let(:post_sampler) { Datadog::Tracing::Sampling::RuleSampler.new(rate_limit: 100, default_sample_rate: 1.0) }
        let(:sample_rate) { 1.0 }
        let(:sampling_priority) { keep_priority }

        it_behaves_like 'priority sampling without scaling'
      end

      context 'that drops the trace' do
        let(:post_sampler) { Datadog::Tracing::Sampling::RuleSampler.new(rate_limit: 100, default_sample_rate: 0.0) }
        let(:sample_rate) { 0.0 }
        let(:sampling_priority) { drop_priority }
        let(:decision) { nil }

        it_behaves_like 'priority sampling without scaling'
      end
    end
  end

  describe '.sampled?' do
    subject(:sampled?) { described_class.sampled?(priority_sampling) }

    {
      -1 => false,
      0 => false,
      1 => true,
      2 => true
    }.each do |priority_sampling, sampled|
      context "with priority_sampling #{priority_sampling}" do
        let(:priority_sampling) { priority_sampling }
        it { is_expected.to eq(sampled) }
      end
    end
  end
end
