require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::SpanContext do
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
