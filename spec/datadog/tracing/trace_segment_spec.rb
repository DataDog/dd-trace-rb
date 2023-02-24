require 'spec_helper'

require 'datadog/core/environment/identity'
require 'datadog/tracing/sampling/ext'
require 'datadog/tracing/span'
require 'datadog/tracing/trace_segment'

RSpec.describe Datadog::Tracing::TraceSegment do
  subject(:trace_segment) { described_class.new(spans, **options) }
  let(:options) { {} }

  let(:spans) do
    Array.new(3) do |i|
      span = Datadog::Tracing::Span.new(
        'job.work',
        resource: 'generate_report',
        service: 'jobs-worker',
        type: 'worker'
      )

      span.set_tag('component', 'sidekiq')
      span.set_tag('job.id', i)
      span
    end
  end

  describe '::new' do
    context 'by default' do
      it do
        is_expected.to have_attributes(
          agent_sample_rate: nil,
          hostname: nil,
          id: nil,
          lang: nil,
          name: nil,
          origin: nil,
          process_id: nil,
          rate_limiter_rate: nil,
          resource: nil,
          rule_sample_rate: nil,
          runtime_id: nil,
          sample_rate: nil,
          sampling_priority: nil,
          service: nil,
          spans: spans,
        )
      end

      it do
        expect(trace_segment.send(:meta)).to eq({})
      end

      it do
        expect(trace_segment.send(:metrics)).to eq({})
      end
    end

    context 'given arguments' do
      context ':agent_sample_rate' do
        let(:options) { { agent_sample_rate: agent_sample_rate } }
        let(:agent_sample_rate) { rand }

        it { is_expected.to have_attributes(agent_sample_rate: agent_sample_rate) }
      end

      context ':hostname' do
        let(:options) { { hostname: hostname } }
        let(:hostname) { 'my.host' }

        it { is_expected.to have_attributes(hostname: be(hostname)) }
      end

      context ':lang' do
        let(:options) { { lang: lang } }
        let(:lang) { 'ruby' }

        it { is_expected.to have_attributes(lang: be(lang)) }
      end

      context ':name' do
        let(:options) { { name: name } }
        let(:name) { 'job.work' }

        it { is_expected.to have_attributes(name: be_a_copy_of(name)) }
      end

      context ':origin' do
        let(:options) { { origin: origin } }
        let(:origin) { 'synthetics' }

        it { is_expected.to have_attributes(origin: be_a_copy_of(origin)) }
      end

      context ':process_id' do
        let(:options) { { process_id: process_id } }
        let(:process_id) { Datadog::Core::Environment::Identity.pid }

        it { is_expected.to have_attributes(process_id: process_id) }
      end

      context ':rate_limiter_rate' do
        let(:options) { { rate_limiter_rate: rate_limiter_rate } }
        let(:rate_limiter_rate) { rand }

        it { is_expected.to have_attributes(rate_limiter_rate: rate_limiter_rate) }
      end

      context ':resource' do
        let(:options) { { resource: resource } }
        let(:resource) { 'generate_report' }

        it { is_expected.to have_attributes(resource: be_a_copy_of(resource)) }
      end

      context ':rule_sample_rate' do
        let(:options) { { rule_sample_rate: rule_sample_rate } }
        let(:rule_sample_rate) { rand }

        it { is_expected.to have_attributes(rule_sample_rate: rule_sample_rate) }
      end

      context ':runtime_id' do
        let(:options) { { runtime_id: runtime_id } }
        let(:runtime_id) { Datadog::Core::Environment::Identity.id }

        it { is_expected.to have_attributes(runtime_id: runtime_id) }
      end

      context ':sample_rate' do
        let(:options) { { sample_rate: sample_rate } }
        let(:sample_rate) { rand }

        it { is_expected.to have_attributes(sample_rate: sample_rate) }
      end

      context ':sampling_priority' do
        let(:options) { { sampling_priority: sampling_priority } }
        let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP }

        it { is_expected.to have_attributes(sampling_priority: sampling_priority) }
      end

      context ':service' do
        let(:options) { { service: service } }
        let(:service) { 'job-worker' }

        it { is_expected.to have_attributes(service: be_a_copy_of(service)) }
      end

      context ':tags' do
        let(:options) { { tags: tags } }
        let(:tags) { { 'foo' => 'bar' } }

        it { expect(trace_segment.send(:meta)).to eq({ 'foo' => 'bar' }) }
      end

      context ':metrics' do
        let(:options) { { metrics: metrics } }
        let(:metrics) { { 'foo' => 42.0 } }

        it { expect(trace_segment.send(:metrics)).to eq({ 'foo' => 42.0 }) }
      end
    end

    context 'given tags' do
      context ':agent_sample_rate' do
        let(:options) { { metrics: { Datadog::Tracing::Metadata::Ext::Sampling::TAG_AGENT_RATE => agent_sample_rate } } }
        let(:agent_sample_rate) { rand }

        it { is_expected.to have_attributes(agent_sample_rate: agent_sample_rate) }
      end

      context ':hostname' do
        let(:options) { { tags: { Datadog::Tracing::Metadata::Ext::NET::TAG_HOSTNAME => hostname } } }
        let(:hostname) { 'my.host' }

        it { is_expected.to have_attributes(hostname: be(hostname)) }
      end

      context ':lang' do
        let(:options) { { tags: { Datadog::Core::Runtime::Ext::TAG_LANG => lang } } }
        let(:lang) { 'ruby' }

        it { is_expected.to have_attributes(lang: be(lang)) }
      end

      context ':name' do
        let(:options) { { tags: { Datadog::Tracing::TraceSegment::TAG_NAME => name } } }
        let(:name) { 'job.work' }

        it { is_expected.to have_attributes(name: be_a_copy_of(name)) }
      end

      context ':origin' do
        let(:options) { { tags: { Datadog::Tracing::Metadata::Ext::Distributed::TAG_ORIGIN => origin } } }
        let(:origin) { 'synthetics' }

        it { is_expected.to have_attributes(origin: be_a_copy_of(origin)) }
      end

      context ':process_id' do
        let(:options) { { tags: { Datadog::Core::Runtime::Ext::TAG_PROCESS_ID => process_id } } }
        let(:process_id) { Datadog::Core::Environment::Identity.pid }

        it { is_expected.to have_attributes(process_id: process_id) }
      end

      context ':rate_limiter_rate' do
        let(:options) do
          { metrics: { Datadog::Tracing::Metadata::Ext::Sampling::TAG_RATE_LIMITER_RATE => rate_limiter_rate } }
        end
        let(:rate_limiter_rate) { rand }

        it { is_expected.to have_attributes(rate_limiter_rate: rate_limiter_rate) }
      end

      context ':resource' do
        let(:options) { { tags: { Datadog::Tracing::TraceSegment::TAG_RESOURCE => resource } } }
        let(:resource) { 'generate_report' }

        it { is_expected.to have_attributes(resource: be_a_copy_of(resource)) }
      end

      context ':rule_sample_rate' do
        let(:options) do
          { metrics: { Datadog::Tracing::Metadata::Ext::Sampling::TAG_RULE_SAMPLE_RATE => rule_sample_rate } }
        end
        let(:rule_sample_rate) { rand }

        it { is_expected.to have_attributes(rule_sample_rate: rule_sample_rate) }
      end

      context ':runtime_id' do
        let(:options) { { tags: { Datadog::Core::Runtime::Ext::TAG_ID => runtime_id } } }
        let(:runtime_id) { Datadog::Core::Environment::Identity.id }

        it { is_expected.to have_attributes(runtime_id: runtime_id) }
      end

      context ':sample_rate' do
        let(:options) { { metrics: { Datadog::Tracing::Metadata::Ext::Sampling::TAG_SAMPLE_RATE => sample_rate } } }
        let(:sample_rate) { rand }

        it { is_expected.to have_attributes(sample_rate: sample_rate) }
      end

      context ':sampling_decision_maker' do
        let(:options) { { tags: { '_dd.p.dm' => sampling_decision_maker } } }
        let(:sampling_decision_maker) { '-1' }

        it { is_expected.to have_attributes(sampling_decision_maker: sampling_decision_maker) }
      end

      context ':sampling_priority' do
        let(:options) do
          { tags: { Datadog::Tracing::Metadata::Ext::Distributed::TAG_SAMPLING_PRIORITY => sampling_priority } }
        end
        let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP }

        it { is_expected.to have_attributes(sampling_priority: sampling_priority) }
      end

      context ':service' do
        let(:options) { { tags: { Datadog::Tracing::TraceSegment::TAG_SERVICE => service } } }
        let(:service) { 'job-worker' }

        it { is_expected.to have_attributes(service: be_a_copy_of(service)) }
      end
    end
  end

  describe 'forwarded #spans methods' do
    [
      :any?,
      :count,
      :empty?,
      :length,
      :size
    ].each do |forwarded_method|
      describe "##{forwarded_method}" do
        it 'forwards to #spans' do
          expect(spans).to receive(forwarded_method)
          trace_segment.send(forwarded_method)
        end
      end
    end
  end

  describe '#keep!' do
    subject(:keep!) { trace_segment.keep! }

    it do
      expect { keep! }
        .to change { trace_segment.sampling_priority }
        .from(nil)
        .to(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)
    end
  end

  describe '#reject!' do
    subject(:reject!) { trace_segment.reject! }

    it do
      expect { reject! }
        .to change { trace_segment.sampling_priority }
        .from(nil)
        .to(Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT)
    end
  end

  describe '#sampled?' do
    subject(:sampled?) { trace_segment.sampled? }
    let(:options) { { sampling_priority: sampling_priority } }
    let(:sampling_priority) { nil }

    context 'when sampling priority is not set' do
      it { is_expected.to be false }
    end

    context 'when sampling priority is set to AUTO_KEEP' do
      let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP }

      it { is_expected.to be true }
    end

    context 'when sampling priority is set to USER_KEEP' do
      let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP }

      it { is_expected.to be true }
    end

    context 'when sampling priority is set to AUTO_REJECT' do
      let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::AUTO_REJECT }

      it { is_expected.to be false }
    end

    context 'when sampling priority is set to USER_REJECT' do
      let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT }

      it { is_expected.to be false }
    end
  end
end
