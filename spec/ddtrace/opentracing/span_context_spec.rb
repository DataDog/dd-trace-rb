require 'spec_helper'

require 'ddtrace/opentracing'
require 'ddtrace/opentracing/helper'

if Datadog::OpenTracing.supported?
  RSpec.describe Datadog::OpenTracing::SpanContext do
    include_context 'OpenTracing helpers'

    subject(:span_context) { described_class.new }

    it { is_expected.to have_attributes(baggage: nil) }

    describe '#initialize' do
      context 'given baggage' do
        subject(:span_context) { described_class.new(baggage: baggage) }
        let(:baggage) { { account_id: '1234' } }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end
  end
end
