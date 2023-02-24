require 'spec_helper'

require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::Propagator do
  describe 'implemented class behavior' do
    subject(:propagator_class) do
      stub_const(
        'TestPropagator',
        Class.new.tap do |klass|
          klass.extend(described_class)
        end
      )
    end

    describe '#inject' do
      let(:span_context) { instance_double(Datadog::OpenTracer::SpanContext) }
      let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }

      it { expect { propagator_class.inject(span_context, carrier) }.to raise_error(NotImplementedError) }
    end

    describe '#extract' do
      let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }

      it { expect { propagator_class.extract(carrier) }.to raise_error(NotImplementedError) }
    end
  end
end
