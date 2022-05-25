# typed: false

require 'spec_helper'
require_relative 'support/helper'

require 'datadog/tracing/pipeline/span_filter'
require 'datadog/tracing/trace_segment'

RSpec.describe Datadog::Tracing::Pipeline::SpanFilter do
  include PipelineHelpers

  let(:trace) { Datadog::Tracing::TraceSegment.new([span_a, span_b, span_c]) }
  let(:span_a) { generate_span('a') }
  let(:span_b) { generate_span('b') }
  let(:span_c) { generate_span('c') }

  context 'with no filtering behavior' do
    subject(:span_filter) { described_class.new { |_| false } }

    it 'does not filter any spans by default' do
      expect { span_filter.call(trace) }
        .to_not(change { trace.spans })
    end
  end

  context 'with a filter applied to spans' do
    subject(:span_filter) { described_class.new { |span| span.name[filter_regex] } }
    let(:filter_regex) { /a|b/ }

    it 'filters out spans that match the filtering criteria' do
      expect { span_filter.call(trace) }
        .to change { trace.spans }
        .from([span_a, span_b, span_c])
        .to([span_c])
    end

    context 'with spans that have a parent' do
      let(:trace) { Datadog::Tracing::TraceSegment.new(spans.dup) }

      let(:spans) { [span_a, span_b, span_c, span_d] }
      let(:filter_regex) { /a/ }
      let(:span_b) { generate_span('b', span_a) }
      let(:span_c) { generate_span('c', span_b) }
      let(:span_d) { generate_span('d') }

      it 'filters out any child spans of a span that matches the criteria' do
        expect { span_filter.call(trace) }.to change { trace.spans }.from(spans).to([span_d])
      end

      context 'with spans that have a parent span that doesnt match filtering criteria' do
        let(:filter_regex) { /b/ }

        it 'does not filter out parent spans of child spans that matches the criteria' do
          expect { span_filter.call(trace) }
            .to change { trace.spans }.from(spans).to([span_a, span_d])
        end
      end

      context 'and are not ordered in the trace' do
        let(:spans) { [span_b, span_d, span_a, span_c] }

        it 'filters out any child spans of a span that matches the criteria' do
          expect { span_filter.call(trace) }.to change { trace.spans }.from(spans).to([span_d])
        end
      end
    end
  end

  context 'with a filter that raises an exception' do
    subject(:span_filter) do
      described_class.new do |span|
        span.name[/b/] || raise('Boom')
      end
    end

    it 'does not filter spans that raise an exception' do
      expect { span_filter.call(trace) }
        .to change { trace.spans }
        .from([span_a, span_b, span_c])
        .to([span_a, span_c])
    end
  end
end
