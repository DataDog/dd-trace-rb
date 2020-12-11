require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Context do
  subject(:context) { described_class.new(options) }
  let(:options) { {} }
  let(:tracer) { get_test_tracer }

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
    subject(:add_span) { context.add_span(span) }

    let(:span) { new_span }

    def new_span
      instance_double(
        Datadog::Span,
        name: double('name'),
        trace_id: double('trace ID'),
        span_id: double('span ID'),
        sampled: double('sampled')
      ).tap do |span|
        allow(span).to receive(:context=)
      end
    end

    context 'given a span' do
      context 'that causes an overflow' do
        include_context 'health metrics'

        let(:existing_span) { new_span }
        let(:overflow_span) { new_span }

        let(:options) { { max_length: max_length } }
        let(:max_length) { 1 }
        before { allow(Datadog.logger).to receive(:debug) }

        RSpec::Matchers.define :a_context_overflow_error do
          match { |actual| actual.include?('context full') }
        end

        context 'once' do
          before do
            context.add_span(existing_span)
            context.add_span(overflow_span)
          end

          it 'doesn\'t add the span to the context' do
            expect(context.current_span).to be existing_span
          end

          it 'sends overflow metric' do
            expect(overflow_span).to have_received(:context=).with(nil)
            expect(Datadog.logger).to have_received(:debug)
              .with(a_context_overflow_error)
            expect(health_metrics).to have_received(:error_context_overflow)
              .with(1, tags: ["max_length:#{max_length}"])
          end
        end

        context 'twice' do
          before do
            context.add_span(existing_span)
            2.times { context.add_span(overflow_span) }
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
            context.add_span(existing_span)
            context.add_span(overflow_span)
            context.send(:reset)
            context.add_span(existing_span)
            context.add_span(overflow_span)
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
    subject(:close_span) { context.close_span(span) }

    let(:span) { new_span }

    def new_span(name = nil)
      instance_double(
        Datadog::Span,
        name: name || double('name'),
        trace_id: double('trace ID'),
        span_id: double('span ID'),
        parent: double('parent ID'),
        sampled: double('sampled'),
        tracer: instance_double(Datadog::Tracer),
        finished?: false
      ).tap do |span|
        allow(span).to receive(:context=)
      end
    end

    before { context.add_span(span) }

    context 'given a root span' do
      let(:span) do
        new_span('root.span').tap do |span|
          allow(span).to receive(:parent).and_return(nil)
          allow(span).to receive(:finished?).and_return(true)
        end
      end

      context 'when the context has unfinished spans' do
        include_context 'health metrics'

        def new_unfinished_span(name = nil)
          new_span(name || 'unfinished.span').tap do |span|
            allow(span).to receive(:parent).and_return(span)
            allow(span).to receive(:finished?).and_return(false)
          end
        end

        let(:unfinished_span) { new_unfinished_span }

        RSpec::Matchers.define :an_unfinished_spans_error do |name, count|
          match { |actual| actual.include?("root span #{name} closed but has #{count} unfinished spans:") }
        end

        RSpec::Matchers.define :an_unfinished_span_error do
          match { |actual| actual.include?('unfinished span:') }
        end

        context 'when debug mode is on' do
          before do
            allow(Datadog.configuration.diagnostics).to receive(:debug).and_return(true)
            allow(Datadog.logger).to receive(:debug)
            context.add_span(unfinished_span)
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
            context.add_span(unfinished_span)
            close_span
          end

          it 'sends an unfinished span error metric' do
            expect(health_metrics).to have_received(:error_unfinished_spans)
              .with(1, tags: ['name:unfinished.span']).once
          end
        end

        context 'of multiple types' do
          before do
            context.add_span(new_unfinished_span('unfinished.span.one'))
            context.add_span(new_unfinished_span('unfinished.span.one'))
            context.add_span(new_unfinished_span('unfinished.span.two'))
            context.add_span(new_unfinished_span('unfinished.span.two'))
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
      let(:span) { Datadog::Span.new(nil, 'dummy') }
      let(:trace) { [span] }
      let(:sampled) { double('sampled flag') }

      before do
        span.sampled = sampled
        context.add_span(span)

        allow(context).to receive(:annotate_for_flush!)
      end

      context 'unfinished' do
        it { is_expected.to eq([nil, sampled]) }

        it 'does not configure unfinished root span' do
          subject
          expect(context).to_not have_received(:annotate_for_flush!)
        end
      end

      context 'finished' do
        before do
          context.close_span(span)
        end

        it { is_expected.to eq([trace, sampled]) }

        it 'configures root span' do
          subject
          expect(context).to have_received(:annotate_for_flush!)
        end
      end
    end
  end

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
    subject(:annotate_for_flush!) { context.delete_span_if(&block) }

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

  describe '#annotate_for_flush!' do
    subject(:annotate_for_flush!) { context.annotate_for_flush!(root_span) }
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

  describe '#length' do
    subject(:ctx) { context }
    let(:span) { new_span }

    def new_span(name = nil)
      Datadog::Span.new(get_test_tracer, name)
    end

    context 'with many spans' do
      it 'should track the number of spans added to the trace' do
        10.times do |i|
          span_to_add = span
          expect(ctx.send(:length)).to eq(i)
          ctx.add_span(span_to_add)
          expect(ctx.send(:length)).to eq(i + 1)
          ctx.close_span(span_to_add)
          expect(ctx.send(:length)).to eq(i + 1)
        end

        ctx.get
        expect(ctx.send(:length)).to eq(0)
      end
    end
  end

  describe '#start_time' do
    subject(:ctx) { tracer.call_context }
    let(:tracer) { get_test_tracer }

    context 'with no active spans' do
      it 'should not have a start time' do
        expect(ctx.send(:start_time)).to be nil
      end
    end

    context 'with a span in the trace' do
      it 'should track start time of the span when trace is active' do
        expect(ctx.send(:start_time)).to be nil

        tracer.trace('test.op') do |span|
          expect(ctx.send(:start_time)).to eq(span.start_time)
          expect(ctx.send(:start_time)).to_not be nil
        end

        expect(ctx.send(:start_time)).to be nil
      end
    end
  end

  describe '#each_span' do
    subject(:ctx) { context }

    def new_span(name = nil)
      Datadog::Span.new(get_test_tracer, name)
    end

    context 'with a span in the trace' do
      it 'should iterate over all the spans available' do
        test_name = 'op.test'
        new_span(test_name)

        ctx.send(:each_span) do |span|
          expect(span.name).to eq(test_name)
        end
      end
    end
  end

  describe 'thread safe behavior' do
    def new_span(name = nil)
      Datadog::Span.new(get_test_tracer, name)
    end

    context 'with many threads' do
      it 'should be threadsafe' do
        n = 100
        threads = []
        spans = []
        mutex = Mutex.new

        n.times do |i|
          threads << Thread.new do
            span = new_span("test.op#{i}")
            context.add_span(span)
            mutex.synchronize do
              spans << span
            end
          end
        end
        threads.each(&:join)

        threads = []
        spans.each do |span|
          threads << Thread.new do
            context.close_span(span)
          end
        end
        threads.each(&:join)

        trace, sampled = context.get

        expect(trace.length).to eq(n)
        expect(sampled).to be true
        expect(context.finished_span_count).to eq(0)
        expect(context.current_span).to be nil
        expect(context.sampled?).to be false
      end
    end
  end
end
