# typed: false
require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Context do
  subject(:context) { described_class.new(options) }

  let(:options) { {} }

  describe '#initialize' do
    context 'with defaults' do
      it do
        is_expected.to have_attributes(
          max_length: described_class::DEFAULT_MAX_LENGTH,
          trace_id: nil,
          span_id: nil,
          sampled?: false,
          sampling_priority: nil,
          origin: nil
        )
      end
    end

    context 'given a' do
      [
        :max_length,
        :trace_id,
        :span_id,
        :sampling_priority,
        :origin
      ].each do |option_name|
        context ":#{option_name} option" do
          let(:options) { { option_name => option_value } }
          let(:option_value) { double(option_name.to_s) }

          it { expect(context.send(option_name)).to eq(option_value) }
        end
      end
    end

    context 'given a :sampled option' do
      let(:options) { { sampled: sampled } }
      let(:sampled) { double('sampled') }

      it { expect(context.sampled?).to eq(sampled) }
    end

    context 'given a sampling_priority' do
      [Datadog::Ext::Priority::USER_REJECT,
       Datadog::Ext::Priority::AUTO_REJECT,
       Datadog::Ext::Priority::AUTO_KEEP,
       Datadog::Ext::Priority::USER_KEEP,
       nil, 999].each do |sampling_priority|
        context ": #{sampling_priority} sampling_priority" do
          let(:options) { { sampling_priority: sampling_priority } }

          if sampling_priority
            it { expect(context.sampling_priority).to eq(sampling_priority) }
          else
            it { expect(context.sampling_priority).to be nil }
          end
        end
      end
    end
  end

  describe '#add_span' do
    subject(:add_span) { context.add_span(span_op) }

    let(:span_op) { new_span_op }

    def new_span_op
      Datadog::SpanOperation.new(double('name'))
    end

    context 'given a span operation' do
      context 'that causes an overflow' do
        include_context 'health metrics'

        let(:existing_span_op) { new_span_op }
        let(:overflow_span_op) { new_span_op }

        let(:options) { { max_length: max_length } }
        let(:max_length) { 1 }

        before { allow(Datadog.logger).to receive(:debug) }

        RSpec::Matchers.define :a_context_overflow_error do
          match { |actual| actual.include?('context full') }
        end

        context 'once' do
          before do
            context.add_span(existing_span_op)
            context.add_span(overflow_span_op)
          end

          it 'doesn\'t add the span operation to the context' do
            expect(context.current_span_op).to be existing_span_op
            is_expected.to be false
          end

          it 'sends overflow metric' do
            expect(Datadog.logger).to have_received(:debug)
              .with(a_context_overflow_error)
            expect(health_metrics).to have_received(:error_context_overflow)
              .with(1, tags: ["max_length:#{max_length}"])
          end
        end

        context 'twice' do
          before do
            context.add_span(existing_span_op)
            2.times { context.add_span(overflow_span_op) }
          end

          it 'sends overflow metric only once' do
            expect(Datadog.logger).to have_received(:debug)
              .with(a_context_overflow_error)
              .twice
            expect(health_metrics).to have_received(:error_context_overflow)
              .with(1, tags: ["max_length:#{max_length}"])
              .once
          end
        end

        context 'twice after previously overflowing and resetting' do
          before do
            context.add_span(existing_span_op)
            context.add_span(overflow_span_op)
            context.send(:reset)
            context.add_span(existing_span_op)
            context.add_span(overflow_span_op)
          end

          it 'sends overflow metric once per reset' do
            expect(Datadog.logger).to have_received(:debug)
              .with(a_context_overflow_error)
              .twice
            expect(health_metrics).to have_received(:error_context_overflow)
              .with(1, tags: ["max_length:#{max_length}"])
              .twice
          end
        end
      end
    end
  end

  describe '#close_span' do
    subject(:close_span) { context.close_span(span_op) }

    let(:span_op) { new_span_op }

    def new_span_op(name = nil)
      Datadog::SpanOperation.new(name || double('name'))
    end

    before { context.add_span(span_op) }

    context 'given a root span operation' do
      let(:span_op) do
        new_span_op('root.span').tap do |span_op|
          allow(span_op).to receive(:parent).and_return(nil)
          allow(span_op).to receive(:finished?).and_return(true)
        end
      end

      context 'when the context has unfinished spans' do
        include_context 'health metrics'

        def new_unfinished_span_op(name = nil)
          new_span_op(name || 'unfinished.span').tap do |span_op|
            allow(span_op).to receive(:parent).and_return(span_op)
            allow(span_op).to receive(:finished?).and_return(false)
          end
        end

        let(:unfinished_span_op) { new_unfinished_span_op }

        RSpec::Matchers.define :an_unfinished_spans_error do |name, count|
          match { |actual| actual.include?("Root span #{name} closed but has #{count} unfinished spans:") }
        end

        RSpec::Matchers.define :an_unfinished_span_error do
          match { |actual| actual.include?('Unfinished span:') }
        end

        context 'when debug mode is on' do
          before do
            allow(Datadog.configuration.diagnostics).to receive(:debug).and_return(true)
            allow(Datadog.logger).to receive(:debug)
            context.add_span(unfinished_span_op)
            close_span
          end

          it 'logs debug messages' do
            expect(Datadog.logger).to have_received(:debug)
              .with(an_unfinished_spans_error('root.span', 1))

            expect(Datadog.logger).to have_received(:debug)
              .with(an_unfinished_span_error).once
          end
        end

        context 'of one type' do
          before do
            context.add_span(unfinished_span_op)
            close_span
          end

          it 'sends an unfinished span error metric' do
            expect(health_metrics).to have_received(:error_unfinished_spans)
              .with(1, tags: ['name:unfinished.span']).once
          end
        end

        context 'of multiple types' do
          before do
            context.add_span(new_unfinished_span_op('unfinished.span.one'))
            context.add_span(new_unfinished_span_op('unfinished.span.one'))
            context.add_span(new_unfinished_span_op('unfinished.span.two'))
            context.add_span(new_unfinished_span_op('unfinished.span.two'))
            close_span
          end

          it 'sends unfinished span error metrics per kind of unfinished span' do
            expect(health_metrics).to have_received(:error_unfinished_spans)
              .with(2, tags: ['name:unfinished.span.one']).once

            expect(health_metrics).to have_received(:error_unfinished_spans)
              .with(2, tags: ['name:unfinished.span.two']).once
          end
        end
      end
    end
  end

  describe '#get' do
    subject(:get) { context.get }

    context 'with no trace' do
      it { is_expected.to eq([nil, false]) }
    end

    context 'with a trace' do
      let(:span_op) { Datadog::SpanOperation.new('dummy') }
      let(:trace) { [span_op] }
      let(:sampled) { double('sampled flag') }

      before do
        span_op.sampled = sampled
        context.add_span(span_op)

        allow(context).to receive(:annotate_for_flush!)
      end

      context 'unfinished' do
        it { is_expected.to eq([nil, sampled]) }

        it 'does not configure unfinished root span operation' do
          subject
          expect(context).to_not have_received(:annotate_for_flush!)
        end
      end

      context 'finished' do
        before do
          context.close_span(span_op)
        end

        it { is_expected.to eq([trace.collect(&:span), sampled]) }

        it 'configures root span' do
          subject
          expect(context).to have_received(:annotate_for_flush!)
        end

        context 'and a block' do
          it { expect { |b| context.get(&b) }.to yield_with_args(trace) }
        end
      end
    end
  end

  describe '#current_root_span_op' do
    subject(:current_root_span_op) { context.current_root_span_op }

    it { is_expected.to be nil }

    context 'after a span is added' do
      let(:span_op) { Datadog::SpanOperation.new('span.one', context: context) }

      before { context.add_span(span_op) }

      it { is_expected.to be span_op }

      context 'which is a child to another span' do
        let(:parent_span_op) { Datadog::SpanOperation.new('span.parent', context: context) }

        let(:span_op) do
          Datadog::SpanOperation.new('span.child', context: context).tap do |op|
            op.parent = parent_span_op
          end
        end

        # Do not set the root span to the parent(?)
        # Presumably because the parent span wasn't added
        # to the context itself, so it can't be the root.
        it { is_expected.to be span_op }
      end

      context 'and is reset' do
        before { context.send(:reset) }

        it { is_expected.to be nil }
      end

      context 'followed by a second span' do
        let(:span_op_two) { Datadog::SpanOperation.new('span.two', context: context) }
        before { context.add_span(span_op_two) }
        it { is_expected.to be span_op }
      end
    end
  end

  describe '#current_span_and_root_span_ops' do
    subject(:current_span_and_root_span_ops) { context.current_span_and_root_span_ops }

    let(:span_op) { Datadog::SpanOperation.new('span', context: context) }
    let(:root_span_op) { Datadog::SpanOperation.new('root span', context: context) }

    it 'returns the current span as well as the current root span' do
      context.add_span(root_span_op)
      context.add_span(span_op)

      current_span_op, current_root_span_op = current_span_and_root_span_ops

      expect(current_span_op).to be span_op
      expect(current_span_op).to be context.current_span_op
      expect(current_root_span_op).to be root_span_op
      expect(current_root_span_op).to be context.current_root_span_op
    end
  end

  describe '#origin' do
    context 'with nil' do
      before { context.origin = nil }

      it { expect(context.origin).to be_nil }
    end

    context 'with empty string' do
      # We do not do any filtering based on value
      before { context.origin = '' }

      it { expect(context.origin).to eq('') }
    end

    context 'with synthetics' do
      before { context.origin = 'synthetics' }

      it { expect(context.origin).to eq('synthetics') }
    end
  end

  describe '#delete_span_if' do
    subject(:annotate_for_flush!) { context.delete_span_if(&block) }

    context 'when the Context contains spans' do
      let(:remaining_span_op) do
        Datadog::SpanOperation.new('span.remaining')
      end

      let(:deleted_span_op) do
        Datadog::SpanOperation.new('deleted')
      end

      let(:block) { proc { |s| s == deleted_span_op } }

      before do
        [remaining_span_op, deleted_span_op].each do |span_op|
          context.add_span(span_op)
          span_op.finish
          context.close_span(span_op)
        end
      end

      it 'returns deleted spans' do
        is_expected.to contain_exactly(deleted_span_op.span)
      end

      it 'keeps spans not deleted' do
        expect { subject }.to change { context.finished_span_count }.from(2).to(1)

        expect(context.get[0]).to contain_exactly(remaining_span_op.span)
      end

      it 'decrements the finished span count' do
        expect { subject }.to change { context.finished_span_count }.from(2).to(1)
      end
    end
  end

  describe '#annotate_for_flush!' do
    subject(:annotate_for_flush!) { context.annotate_for_flush!(root_span_op) }

    let(:root_span_op) { Datadog::SpanOperation.new('dummy') }

    let(:options) { { origin: origin, sampled: sampled, sampling_priority: sampling_priority } }

    let(:origin) { nil }
    let(:sampled) { nil }
    let(:sampling_priority) { nil }

    before do
      context.add_span(root_span_op)

      subject
    end

    context 'with origin' do
      let(:origin) { 'origin_1' }

      it do
        expect(root_span_op.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)).to eq(origin)
      end
    end

    context 'with sampling priority' do
      let(:sampled) { true }
      let(:sampling_priority) { 1 }

      it do
        expect(root_span_op.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(sampling_priority)
      end
    end
  end

  describe '#attach_sampling_priority' do
    subject(:attach_sampling_priority) { context.attach_sampling_priority(span_op) }
    let(:span_op) { instance_double(Datadog::SpanOperation) }

    before { allow(span_op).to receive(:set_metric) }

    context 'when origin is set' do
      let(:sampling_priority) { 99 }

      before do
        context.sampling_priority = sampling_priority
        attach_sampling_priority
      end

      it do
        expect(span_op)
          .to have_received(:set_metric)
          .with(
            Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY,
            sampling_priority
          )
      end
    end
  end

  describe '#attach_origin' do
    subject(:attach_origin) { context.attach_origin(span_op) }
    let(:span_op) { instance_double(Datadog::SpanOperation) }

    before { allow(span_op).to receive(:set_tag) }

    context 'when origin is set' do
      let(:origin) { 'my-origin' }

      before do
        context.origin = origin
        attach_origin
      end

      it do
        expect(span_op)
          .to have_received(:set_tag)
          .with(
            Datadog::Ext::DistributedTracing::ORIGIN_KEY,
            origin
          )
      end
    end
  end

  describe '#fork_clone' do
    subject(:fork_clone) { context.fork_clone }

    let(:options) do
      {
        trace_id: SecureRandom.uuid,
        span_id: SecureRandom.uuid,
        sampled: true,
        sampling_priority: Datadog::Ext::Priority::AUTO_KEEP,
        origin: 'synthetics'
      }
    end

    it do
      is_expected.to be_a_kind_of(described_class)
      is_expected.to have_attributes(
        trace_id: context.trace_id,
        span_id: context.span_id,
        sampled?: context.sampled?,
        sampling_priority: context.sampling_priority,
        origin: context.origin
      )
    end
  end

  describe 'thread safe behavior' do
    def new_span_op(name = nil)
      Datadog::SpanOperation.new(name)
    end

    context 'with many threads' do
      it 'is threadsafe' do
        n = 100
        threads = []
        span_ops = []
        mutex = Mutex.new

        n.times do |i|
          threads << Thread.new do
            span_op = new_span_op("test.op#{i}")
            context.add_span(span_op)
            mutex.synchronize do
              span_ops << span_op
            end
          end
        end
        threads.each(&:join)

        threads = []
        span_ops.each do |span_op|
          threads << Thread.new do
            context.close_span(span_op)
          end
        end
        threads.each(&:join)

        trace, sampled = context.get

        expect(trace.length).to eq(n)
        expect(sampled).to be true
        expect(context.finished_span_count).to eq(0)
        expect(context.current_span_op).to be nil
        expect(context.sampled?).to be false
      end
    end
  end
end
