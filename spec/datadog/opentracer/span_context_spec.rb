require 'spec_helper'

require 'datadog/tracing/context'
require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::SpanContext do
  describe '#initialize' do
    context 'given a Datadog::Context' do
      subject(:span_context) { described_class.new(datadog_context: datadog_context) }

      let(:datadog_context) { instance_double(Datadog::Tracing::Context) }

      it do
        is_expected.to have_attributes(
          datadog_context: datadog_context,
          baggage: {}
        )
      end

      context 'and baggage' do
        subject(:span_context) do
          described_class.new(
            datadog_context: datadog_context,
            baggage: original_baggage
          )
        end

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
