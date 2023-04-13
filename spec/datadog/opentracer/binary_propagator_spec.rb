require 'spec_helper'

require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::BinaryPropagator do
  describe '#inject' do
    subject { described_class.inject(span_context, carrier) }

    let(:span_context) { instance_double(Datadog::OpenTracer::SpanContext) }
    let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }

    it { is_expected.to be nil }
  end

  describe '#extract' do
    subject(:span_context) { described_class.extract(carrier) }

    let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }

    it { is_expected.to be(Datadog::OpenTracer::SpanContext::NOOP_INSTANCE) }
  end
end
