# typed: false
require 'datadog/ci/spec_helper'

require 'ddtrace/context'
require 'ddtrace/span'
require 'datadog/ci/context_flush'

RSpec.shared_context 'trace context' do
  let(:context) { instance_double(Datadog::Context) }

  def new_test_span
    test_span = instance_double(Datadog::Span)
    allow(test_span).to receive(:set_tag)
    test_span
  end

  before do
    # Spy to see if Context#attach_origin is called
    allow(context).to receive(:get) do |&block|
      block.call(trace)
      get
    end

    allow(context).to receive(:origin).and_return(origin)
  end

  let(:get) { [trace, sampled] }
  let(:sampled) { true }
  let(:trace) { [new_test_span, new_test_span] }
  let(:origin) { 'test_origin' }
end

RSpec.shared_examples_for 'a context flusher' do
  context 'with request not sampled' do
    let(:sampled) { false }

    it 'returns nil' do
      is_expected.to be_nil
    end
  end

  context 'with request sampled' do
    let(:sampled) { true }

    it 'returns the original trace with origin tags' do
      is_expected.to eq(trace)

      expect(trace).to all(
        have_received(:set_tag).with(
          Datadog::Ext::DistributedTracing::ORIGIN_KEY,
          origin
        )
      )
    end
  end
end

RSpec.describe Datadog::CI::ContextFlush::Finished do
  subject(:context_flush) { described_class.new }

  describe '#consume' do
    subject(:consume) { context_flush.consume!(context) }

    include_context 'trace context'
    it_behaves_like 'a context flusher'
  end
end

RSpec.describe Datadog::CI::ContextFlush::Partial do
  subject(:context_flush) { described_class.new(min_spans_before_partial_flush: min_spans_for_partial) }

  let(:min_spans_for_partial) { 2 }

  describe '#consume' do
    subject(:consume) { context_flush.consume!(context) }

    include_context 'trace context'
    it_behaves_like 'a context flusher'
  end
end
