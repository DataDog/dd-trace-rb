require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::SpanContext do
    include_context 'OpenTracing helpers'

    subject(:span_context) { described_class.new }

    it { is_expected.to have_attributes(baggage: {}) }

    describe '#initialize' do
      context 'given baggage' do
        subject(:span_context) { described_class.new(baggage: original_baggage) }
        let(:original_baggage) { { account_id: '1234' } }

        it { is_expected.to be_a_kind_of(described_class) }

        describe 'builds a SpanContext where' do
          describe '#baggage' do
            subject(:baggage) { span_context.baggage }
            it { is_expected.to be(original_baggage) }
            it 'is immutable' do
              expect { baggage[1] = 2 }.to raise_error(RuntimeError)
            end
          end
        end
      end
    end
  end
end
