require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::SpanContext do
    include_context 'OpenTracing helpers'

    describe '#initialize' do
      context 'given span_id, trace_id, parent_id' do
        subject(:span_context) do
          described_class.new(
            span_id: span_id,
            trace_id: trace_id,
            parent_id: parent_id
          )
        end

        let(:span_id) { double('span_id') }
        let(:trace_id) { double('trace_id') }
        let(:parent_id) { double('parent_id') }

        it do
          is_expected.to have_attributes(
            span_id: span_id,
            trace_id: trace_id,
            parent_id: parent_id,
            baggage: {}
          )
        end

        context 'and baggage' do
          subject(:span_context) do
            described_class.new(
              span_id: span_id,
              trace_id: trace_id,
              parent_id: parent_id,
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
end
