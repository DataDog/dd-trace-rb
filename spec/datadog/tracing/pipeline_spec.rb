require 'spec_helper'

require 'datadog/tracing/pipeline'
require 'datadog/tracing/pipeline/span_filter'
require 'datadog/tracing/pipeline/span_processor'
require 'datadog/tracing/trace_segment'

require_relative 'pipeline/support/helper'

RSpec.describe Datadog::Tracing::Pipeline do
  include PipelineHelpers

  let(:span_a) { generate_span('a') }
  let(:span_b) { generate_span('b') }
  let(:span_c) { generate_span('c') }
  let(:span_d) { generate_span('d') }
  let(:span_list) { [span_a, span_b, span_c, span_d] }
  let(:callable) { ->(trace) { trace } }
  let(:callable2) { ->(trace) { trace } }

  after do
    described_class.processors = []
  end

  context 'pipeline' do
    subject(:pipeline) { described_class }

    context 'with empty pipeline' do
      let(:trace) { Datadog::Tracing::TraceSegment.new([span_list]) }

      it 'does not modify any spans' do
        expect(pipeline.process!([trace])).to eq([trace])
      end
    end

    context 'with a callable added' do
      it 'allows a callable to be added' do
        expect(pipeline.before_flush(callable)).to eq([callable])
      end

      it 'takes a block as an argument' do
        expect(pipeline.before_flush(&callable)).to eq([callable])
      end

      it 'allows multiple callables as arguments' do
        expect(pipeline.before_flush(callable, callable2, callable)).to eq([callable, callable2, callable])
      end

      it 'concats and store multiple callables' do
        pipeline.before_flush(callable)
        expect(pipeline.before_flush(callable2)).to eq([callable, callable2])
      end

      it 'takes an object and block' do
        expect(pipeline.before_flush(callable, &callable2)).to eq([callable, callable2])
      end
    end

    context 'with a filter added' do
      subject(:filter) { pipeline.process!(traces) }
      let(:span_filter_a) { Datadog::Tracing::Pipeline::SpanFilter.new { |span| span.name[/a/] } }
      let(:span_filter_c) { Datadog::Tracing::Pipeline::SpanFilter.new { |span| span.name[/c/] } }

      context 'given a single trace' do
        let(:traces) { [trace] }
        let(:trace) { Datadog::Tracing::TraceSegment.new(span_list) }

        before { pipeline.before_flush(span_filter_a) }

        it 'applies a callable filter to each trace' do
          is_expected.to eq(traces)
          expect(filter.first.spans).to eq([span_b, span_c, span_d])
        end
      end

      context 'given multiple traces' do
        let(:traces) { [trace_one, trace_two] }
        let(:trace_one) { Datadog::Tracing::TraceSegment.new([span_a, span_b]) }
        let(:trace_two) { Datadog::Tracing::TraceSegment.new([span_c, span_d]) }

        before { pipeline.before_flush(span_filter_a, span_filter_c) }

        it 'applies each callable filter to each trace' do
          is_expected.to eq(traces)
          expect(filter[0].spans).to eq([span_b])
          expect(filter[1].spans).to eq([span_d])
        end
      end
    end

    context 'with a filter and processor added' do
      subject(:filter_and_process) { pipeline.process!(traces) }

      let(:traces) { [trace_one, trace_two] }
      let(:trace_one) { Datadog::Tracing::TraceSegment.new([span_a, span_b]) }
      let(:trace_two) { Datadog::Tracing::TraceSegment.new([span_c, span_d]) }

      let(:span_filter_a) { Datadog::Tracing::Pipeline::SpanFilter.new { |span| span.name[/a/] } }
      let(:span_filter_c) { Datadog::Tracing::Pipeline::SpanFilter.new { |span| span.name[/c/] } }
      let(:span_processor_upcase) { Datadog::Tracing::Pipeline::SpanProcessor.new { |span| span.name.upcase! } }
      let(:span_processor_name) { Datadog::Tracing::Pipeline::SpanProcessor.new { |span| span.name += '!' } }

      before { pipeline.before_flush(span_filter_a, span_filter_c, span_processor_upcase, span_processor_name) }

      it 'applies a callable filter and processor to each trace' do
        is_expected.to eq(traces)
        expect(filter_and_process[0].spans).to eq([span_b])
        expect(filter_and_process[1].spans).to eq([span_d])
        expect(span_b.name).to eq('B!')
        expect(span_d.name).to eq('D!')
      end
    end

    context 'with a custom callable' do
      subject(:custom_process) { pipeline.process!(traces) }

      let(:custom_callable_conditional) do
        lambda do |trace|
          trace if trace.size == 3
        end
      end

      let(:custom_callable_reverse) do
        lambda do |trace|
          trace.spans.reverse!
          trace
        end
      end

      let(:traces) { [trace_one, trace_two] }
      let(:trace_one) { Datadog::Tracing::TraceSegment.new([span_a]) }
      let(:trace_two) { Datadog::Tracing::TraceSegment.new([span_b, span_c, span_d]) }

      before { pipeline.before_flush(custom_callable_conditional, custom_callable_reverse) }

      it 'applies custom callable to each trace' do
        is_expected.to eq([trace_two])
        expect(custom_process.first.spans).to eq([span_d, span_c, span_b])
      end
    end
  end
end
