require 'spec_helper'
require 'ddtrace/pipeline'
require_relative 'pipeline/support/helper'

RSpec.describe Datadog::Pipeline do
  include PipelineHelpers

  let(:span_a) { generate_span('a') }
  let(:span_b) { generate_span('b') }
  let(:span_c) { generate_span('c') }
  let(:span_d) { generate_span('d') }
  let(:span_list) { [span_a, span_b, span_c, span_d] }
  let(:callable) { ->(trace) { trace } }
  let(:custom_callable_conditional) { ->(trace) { trace if trace.size == 3 } }
  let(:custom_callable_reverse) { ->(trace) { trace.reverse } }

  after do
    described_class.processors = []
  end

  context 'pipeline' do
    subject(:pipeline) { described_class }

    context 'with empty pipeline' do
      it 'does not modify any spans' do
        expect(subject.process!([span_list])).to eq([span_list])
      end
    end

    context 'with a callable added' do
      it 'allows a callable to be added' do
        expect(subject.before_flush(callable)).to eq([callable])
      end

      it 'takes a block as an argument' do
        expect(subject.before_flush(&callable)).to eq([callable])
      end

      it 'allows multiple callables as arguments' do
        expect(subject.before_flush(callable, callable, callable)).to eq([callable, callable, callable])
      end

      it 'concats and store multiple callables' do
        subject.before_flush(callable)
        expect(subject.before_flush(callable)).to eq([callable, callable])
      end
    end

    context 'with a filter added' do
      let(:span_filter_a) { Datadog::Pipeline::SpanFilter.new { |span| span.name[/a/] } }
      let(:span_filter_c) { Datadog::Pipeline::SpanFilter.new { |span| span.name[/c/] } }

      it 'applies a callable filter to each trace' do
        subject.before_flush(span_filter_a)

        expect(subject.process!([span_list])).to eq([[span_b, span_c, span_d]])
      end

      it 'applies each callable filter to each trace' do
        subject.before_flush(span_filter_a, span_filter_c)

        expect(subject.process!([[span_a, span_b], [span_c, span_d]])).to eq([[span_b], [span_d]])
      end
    end

    context 'with a filter and processor added' do
      let(:span_filter_a) { Datadog::Pipeline::SpanFilter.new { |span| span.name[/a/] } }
      let(:span_filter_c) { Datadog::Pipeline::SpanFilter.new { |span| span.name[/c/] } }
      let(:span_processor_upcase) { Datadog::Pipeline::SpanProcessor.new { |span| span.name.upcase! } }
      let(:span_processor_name) { Datadog::Pipeline::SpanProcessor.new { |span| span.name += '!' } }

      it 'applies a callable filter and processor to each trace' do
        subject.before_flush(span_filter_a, span_filter_c, span_processor_upcase, span_processor_name)
        expect(subject.process!([[span_a, span_b], [span_c, span_d]])).to eq([[span_b], [span_d]])
        expect(span_b.name).to eq('B!')
        expect(span_d.name).to eq('D!')
      end
    end

    context 'with a custom callable' do
      it 'applies custom callable to each trace' do
        subject.before_flush(custom_callable_conditional, custom_callable_reverse)
        expect(subject.process!([[1], [1, 2], [1, 2, 3]])).to eq([[3, 2, 1]])
      end
    end
  end
end
