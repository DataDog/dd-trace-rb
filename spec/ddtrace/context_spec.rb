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
end
