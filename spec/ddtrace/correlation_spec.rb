require 'spec_helper'

require 'ddtrace/correlation'
require 'ddtrace/context'

RSpec.describe Datadog::Correlation do
  describe '::identifier_from_context' do
    subject(:correlation_ids) { described_class.identifier_from_context(context) }

    context 'given nil' do
      let(:context) { nil }

      it 'returns an empty Correlation::Identifier' do
        is_expected.to be_a_kind_of(Datadog::Correlation::Identifier)
        expect(correlation_ids.trace_id).to be 0
        expect(correlation_ids.span_id).to be 0
      end
    end

    context 'given a Context object' do
      let(:context) do
        instance_double(
          Datadog::Context,
          trace_id: trace_id,
          span_id: span_id
        )
      end

      let(:trace_id) { double('trace id') }
      let(:span_id) { double('span id') }

      it 'returns a Correlation::Identifier matching the Context' do
        is_expected.to be_a_kind_of(Datadog::Correlation::Identifier)
        expect(correlation_ids.trace_id).to eq(trace_id)
        expect(correlation_ids.span_id).to eq(span_id)
      end
    end
  end
end
