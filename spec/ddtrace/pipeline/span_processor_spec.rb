require 'spec_helper'
require 'ddtrace/pipeline'
require_relative 'support/helper'

RSpec.describe Datadog::Pipeline::SpanProcessor do
  include PipelineHelpers

  let(:span_a) { generate_span('a') }
  let(:span_b) { generate_span('b') }
  let(:span_c) { generate_span('c') }
  let(:span_list) { [span_a, span_b, span_c] }

  context 'with no processing behavior' do
    subject(:span_processor) { described_class.new { |_| } }

    it 'does not modify any spans' do
      expect(subject.call(span_list)).to eq(span_list)
    end
  end

  context 'with processing behavior that returns falsey value' do
    subject(:span_processor) { described_class.new { |_| false } }

    it 'does not drop any spans' do
      expect(subject.call(span_list)).to eq(span_list)
    end
  end

  context 'with processing applied to spans' do
    subject(:span_processor) do
      described_class.new do |span|
        span.name += '!'
      end
    end

    it 'modifies spans according to processor criteria' do
      expect(subject.call(span_list).map(&:name)).to eq(['a!', 'b!', 'c!'])
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
      expect(subject.call(span_list).map(&:name)).to eq(['a!', 'b!', 'c!'])
    end
  end
end
