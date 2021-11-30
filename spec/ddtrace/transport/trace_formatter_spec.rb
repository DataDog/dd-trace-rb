# typed: false
require 'spec_helper'

require 'ddtrace/transport/trace_formatter'

RSpec.describe Datadog::Transport::TraceFormatter do
  subject(:trace_formatter) { described_class.new(trace) }
  let(:trace_options) { {} }

  shared_context 'trace metadata' do
    let(:trace_options) do
      {
        resource: resource,
        agent_sample_rate: agent_sample_rate,
        hostname: hostname,
        lang: lang,
        origin: origin,
        process_id: process_id,
        rate_limiter_rate: rate_limiter_rate,
        rule_sample_rate: rule_sample_rate,
        runtime_id: runtime_id,
        sample_rate: sample_rate,
        sampling_priority: sampling_priority
      }
    end

    let(:resource) { 'trace.resource' }
    let(:agent_sample_rate) { rand }
    let(:hostname) { 'trace.hostname' }
    let(:lang) { Datadog::Core::Environment::Identity.lang }
    let(:origin) { 'trace.origin' }
    let(:process_id) { 'trace.process_id' }
    let(:rate_limiter_rate) { rand }
    let(:rule_sample_rate) { rand }
    let(:runtime_id) { 'trace.runtime_id' }
    let(:sample_rate) { rand }
    let(:sampling_priority) { Datadog::Ext::Priority::USER_KEEP }
  end

  shared_context 'no root span' do
    let(:trace) { Datadog::TraceSegment.new(spans, **trace_options) }
    let(:spans) { Array.new(3) { Datadog::Span.new('my.job') } }
    let(:root_span) { spans.last }
  end

  shared_context 'missing root span' do
    let(:trace) { Datadog::TraceSegment.new(spans, root_span_id: Datadog::Utils.next_id, **trace_options) }
    let(:spans) { Array.new(3) { Datadog::Span.new('my.job') } }
    let(:root_span) { spans.last }
  end

  shared_context 'available root span' do
    let(:trace) { Datadog::TraceSegment.new(spans, root_span_id: root_span.id, **trace_options) }
    let(:spans) { Array.new(3) { Datadog::Span.new('my.job') } }
    let(:root_span) { spans[1] }
  end

  describe '::new' do
    context 'given a TraceSegment' do
      shared_examples 'a formatter with root span' do
        it do
          is_expected.to have_attributes(
            trace: trace,
            root_span: root_span
          )
        end
      end

      context 'with no root span' do
        include_context 'no root span'
        it_behaves_like 'a formatter with root span'
      end

      context 'with missing root span' do
        include_context 'missing root span'
        it_behaves_like 'a formatter with root span'
      end

      context 'with a root span' do
        include_context 'available root span'
        it_behaves_like 'a formatter with root span'
      end
    end
  end

  describe '#format!' do
    subject(:format!) { trace_formatter.format! }

    context 'when initialized with a TraceSegment' do
      shared_examples 'root span with no tags' do
        it do
          expect(root_span).to have_metadata(
            Datadog::Ext::Sampling::TAG_AGENT_RATE => nil,
            Datadog::Ext::NET::TAG_HOSTNAME => nil,
            Datadog::Ext::Runtime::TAG_LANG => nil,
            Datadog::Ext::DistributedTracing::TAG_ORIGIN => nil,
            Datadog::Ext::Runtime::TAG_PID => nil,
            Datadog::Ext::Sampling::TAG_RATE_LIMITER_RATE => nil,
            Datadog::Ext::Sampling::TAG_RULE_SAMPLE_RATE => nil,
            Datadog::Ext::Runtime::TAG_ID => nil,
            Datadog::Ext::Sampling::TAG_SAMPLE_RATE => nil,
            Datadog::Ext::DistributedTracing::TAG_SAMPLING_PRIORITY => nil
          )
        end
      end

      shared_examples 'root span with tags' do
        it do
          expect(root_span).to have_metadata(
            Datadog::Ext::Sampling::TAG_AGENT_RATE => agent_sample_rate,
            Datadog::Ext::NET::TAG_HOSTNAME => hostname,
            Datadog::Ext::Runtime::TAG_LANG => lang,
            Datadog::Ext::DistributedTracing::TAG_ORIGIN => origin,
            Datadog::Ext::Runtime::TAG_PID => process_id,
            Datadog::Ext::Sampling::TAG_RATE_LIMITER_RATE => rate_limiter_rate,
            Datadog::Ext::Sampling::TAG_RULE_SAMPLE_RATE => rule_sample_rate,
            Datadog::Ext::Runtime::TAG_ID => runtime_id,
            Datadog::Ext::Sampling::TAG_SAMPLE_RATE => sample_rate,
            Datadog::Ext::DistributedTracing::TAG_SAMPLING_PRIORITY => sampling_priority
          )
        end

        context 'but peer.service is set' do
          before do
            allow(root_span).to receive(:get_tag)
              .with(Datadog::Ext::Integration::TAG_PEER_SERVICE)
              .and_return('a-peer-service')
          end

          it { expect(root_span).to have_metadata(Datadog::Ext::Runtime::TAG_LANG => nil) }
        end
      end

      context 'with no root span' do
        include_context 'no root span'

        before { format! }

        context 'when trace has no metadata set' do
          it { is_expected.to be(trace) }
          it { expect(root_span.resource).to eq('my.job') }

          it_behaves_like 'root span with no tags'
        end

        context 'when trace has metadata set' do
          include_context 'trace metadata'

          it { is_expected.to be(trace) }
          it { expect(root_span.resource).to eq('my.job') }

          it_behaves_like 'root span with tags'
        end
      end

      context 'with missing root span' do
        include_context 'missing root span'

        before { format! }

        context 'when trace has no metadata set' do
          it { is_expected.to be(trace) }
          it { expect(root_span.resource).to eq('my.job') }

          it_behaves_like 'root span with no tags'
        end

        context 'when trace has metadata set' do
          include_context 'trace metadata'

          it { is_expected.to be(trace) }
          it { expect(root_span.resource).to eq('my.job') }

          it_behaves_like 'root span with tags'
        end
      end

      context 'with a root span' do
        include_context 'available root span'

        before { format! }

        context 'when trace has no metadata set' do
          it { is_expected.to be(trace) }
          it { expect(root_span.resource).to eq('my.job') }

          it_behaves_like 'root span with no tags'
        end

        context 'when trace has metadata set' do
          include_context 'trace metadata'

          it { is_expected.to be(trace) }
          it { expect(root_span.resource).to eq(resource) }

          it_behaves_like 'root span with tags'
        end
      end
    end
  end
end
