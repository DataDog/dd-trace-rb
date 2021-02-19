require 'spec_helper'
require 'ddtrace/pipeline'
require_relative 'support/helper'

RSpec.describe Datadog::Pipeline::SpanFilter do
  include PipelineHelpers

  let(:span_a) { generate_span('a') }
  let(:span_b) { generate_span('b') }
  let(:span_c) { generate_span('c') }
  let(:span_list) { [span_a, span_b, span_c] }

  context 'with no filtering behavior' do
    subject(:span_filter) { described_class.new { |_| false } }

    it 'does not filter any spans by default' do
      expect(subject.call(span_list)).to eq(span_list)
    end
  end

  context 'with a filter applied to spans' do
    let(:filter_regex) { /a|b/ }

    subject(:span_filter) { described_class.new { |span| span.name[filter_regex] } }

    it 'filters out spans that match the filtering criteria' do
      expect(subject.call(span_list)).to eq([span_c])
    end

    context 'with spans that have a parent' do
      let(:filter_regex) { /a/ }
      let(:span_b) { generate_span('b', span_a) }
      let(:span_c) { generate_span('c', span_b) }
      let(:span_d) { generate_span('d') }
      let(:span_list) { [span_a, span_b, span_c, span_d] }

      it 'filters out any child spans of a span that matches the criteria' do
        expect(subject.call(span_list)).to eq([span_d])
      end

      context 'with spans that have a parent span that doesnt match filtering criteria' do
        let(:filter_regex) { /b/ }

        it 'does not filter out parent spans of child spans that matches the criteria' do
          expect(subject.call(span_list)).to eq([span_a, span_d])
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
      expect(subject.call(span_list)).to eq([span_a, span_c])
    end
  end
end
