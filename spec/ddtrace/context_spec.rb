require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Context do
  subject(:context) { described_class.new(options) }
  let(:options) { {} }
  let(:tracer) { get_test_tracer }

  describe '#current_root_span' do
    subject(:current_root_span) { context.current_root_span }

    it { is_expected.to be nil }

    context 'after a span is added' do
      let(:span) { Datadog::Span.new(tracer, 'span.one', context: context) }
      before(:each) { context.add_span(span) }

      it { is_expected.to be span }

      context 'which is a child to another span' do
        let(:parent_span) { Datadog::Span.new(tracer, 'span.parent') }
        let(:span) do
          Datadog::Span.new(
            tracer,
            'span.child',
            context: context
          ).tap { |s| s.parent = parent_span }
        end

        it { is_expected.to be span }
      end

      context 'and is reset' do
        before(:each) { context.send(:reset) }
        it { is_expected.to be nil }
      end

      context 'followed by a second span' do
        let(:span_two) { Datadog::Span.new(tracer, 'span.two', context: context) }
        before(:each) { context.add_span(span_two) }
        it { is_expected.to be span }
      end
    end
  end

  describe '#origin' do
    context 'with nil' do
      before(:each) { context.origin = nil }
      it { expect(context.origin).to be_nil }
    end

    context 'with empty string' do
      # We do not do any filtering based on value
      before(:each) { context.origin = '' }
      it { expect(context.origin).to eq('') }
    end

    context 'with synthetics' do
      before(:each) { context.origin = 'synthetics' }
      it { expect(context.origin).to eq('synthetics') }
    end
  end

  describe '#delete_span_if' do
    subject(:configure_root_span) { context.delete_span_if(&block) }

    let(:remaining_span) { Datadog::Span.new(tracer, 'remaining', context: context).tap(&:finish) }
    let(:deleted_span) { Datadog::Span.new(tracer, 'deleted', context: context).tap(&:finish) }
    let(:block) { proc { |s| s == deleted_span } }

    before do
      context.add_span(remaining_span)
      context.add_span(deleted_span)
    end

    it 'returns deleted spans' do
      is_expected.to contain_exactly(deleted_span)
    end

    it 'keeps spans not deleted' do
      expect { subject }.to change { context.finished_span_count }.from(2).to(1)

      expect(context.get[0]).to contain_exactly(remaining_span)
    end

    it 'detaches context from delete span' do
      expect { subject }.to change { deleted_span.context }.from(context).to(nil)
    end
  end

  describe '#configure_root_span' do
    subject(:configure_root_span) { context.configure_root_span }
    let(:root_span) { Datadog::Span.new(nil, 'dummy') }

    let(:options) { { origin: origin, sampled: sampled, sampling_priority: sampling_priority } }

    let(:origin) { nil }
    let(:sampled) { nil }
    let(:sampling_priority) { nil }

    before do
      context.add_span(root_span)

      subject
    end

    context 'with origin' do
      let(:origin) { 'origin_1' }
      it do
        expect(root_span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)).to eq(origin)
      end
    end

    context 'with sampling priority' do
      let(:sampled) { true }
      let(:sampling_priority) { 1 }

      it do
        expect(root_span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(sampling_priority)
      end
    end
  end
end
