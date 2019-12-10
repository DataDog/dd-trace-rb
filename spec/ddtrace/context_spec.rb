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
        before { allow(Datadog::Logger.log).to receive(:debug) }

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
            expect(Datadog::Logger.log).to have_received(:debug)
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
            expect(Datadog::Logger.log).to have_received(:debug)
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
            expect(Datadog::Logger.log).to have_received(:debug)
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

        context 'when tracer debug logging is on' do
          before do
            allow(Datadog::Logger).to receive(:debug_logging).and_return(true)
            allow(Datadog::Logger.log).to receive(:debug)
            context.add_span(unfinished_span)
            close_span
          end

          it 'logs debug messages' do
            expect(Datadog::Logger.log).to have_received(:debug)
              .with(an_unfinished_spans_error('root.span', 1))

            expect(Datadog::Logger.log).to have_received(:debug)
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
end
