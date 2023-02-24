require 'spec_helper'
require_relative 'support/helper'

require 'datadog/tracing/pipeline/span_processor'
require 'datadog/tracing/trace_segment'

RSpec.describe Datadog::Tracing::Pipeline::SpanProcessor do
  include PipelineHelpers

  let(:trace) { Datadog::Tracing::TraceSegment.new([span_a, span_b, span_c]) }
  let(:span_a) { generate_span('a') }
  let(:span_b) { generate_span('b') }
  let(:span_c) { generate_span('c') }

  context 'with no processing behavior' do
    subject(:span_processor) { described_class.new { |_| } }

    it 'does not modify any spans' do
      expect { span_processor.call(trace) }
        .to_not(change { trace.spans })
    end
  end

  context 'with processing behavior that returns falsey value' do
    subject(:span_processor) { described_class.new { |_| false } }

    it 'does not drop any spans' do
      expect { span_processor.call(trace) }
        .to_not(change { trace.spans })
    end
  end

  context 'with processing applied to spans' do
    subject(:span_processor) do
      described_class.new do |span|
        span.name += '!'
      end
    end

    it 'modifies spans according to processor criteria' do
      expect { span_processor.call(trace) }
        .to change { trace.spans.map(&:name) }
        .from(%w[a b c])
        .to(['a!', 'b!', 'c!'])
    end
  end

  context 'with processing that raises an exception' do
    subject(:span_processor) do
      described_class.new do |span|
        span.name += '!'
        raise('Boom')
      end
    end

    it 'modifies spans according to processor criteria and catch exceptions' do
      expect { span_processor.call(trace) }
        .to change { trace.spans.map(&:name) }
        .from(%w[a b c])
        .to(['a!', 'b!', 'c!'])
    end
  end
end
