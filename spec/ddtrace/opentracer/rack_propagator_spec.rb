require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::RackPropagator do
    include_context 'OpenTracing helpers'

    describe '#inject' do
      subject { described_class.inject(span_context, carrier) }

      let(:span_context) do
        instance_double(
          Datadog::OpenTracer::SpanContext,
          datadog_context: datadog_context,
          baggage: baggage
        )
      end

      let(:datadog_context) do
        instance_double(
          Datadog::Context,
          trace_id: trace_id,
          span_id: span_id,
          sampling_priority: sampling_priority
        )
      end

      let(:trace_id) { double('trace ID') }
      let(:span_id) { double('span ID') }
      let(:sampling_priority) { double('sampling priority') }

      let(:baggage) { { 'account_name' => 'acme' } }

      let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }

      # Expect carrier to be set with Datadog trace properties
      before(:each) do
        expect(carrier).to receive(:[]=)
          .with(Datadog::HTTPPropagator::HTTP_HEADER_TRACE_ID, trace_id.to_s)
        expect(carrier).to receive(:[]=)
          .with(Datadog::HTTPPropagator::HTTP_HEADER_PARENT_ID, span_id.to_s)
        expect(carrier).to receive(:[]=)
          .with(Datadog::HTTPPropagator::HTTP_HEADER_SAMPLING_PRIORITY, sampling_priority.to_s)
      end

      # Expect carrier to be set with OpenTracing baggage
      before(:each) do
        baggage.each do |key, value|
          expect(carrier).to receive(:[]=)
            .with(described_class::BAGGAGE_PREFIX + key, value)
        end
      end

      it { is_expected.to be nil }
    end

    describe '#extract' do
      subject(:span_context) { described_class.extract(carrier) }
      let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }
      let(:items) { {} }
      let(:datadog_context) { instance_double(Datadog::Context) }

      before(:each) do
        expect(Datadog::HTTPPropagator).to receive(:extract)
          .with(carrier)
          .and_return(datadog_context)

        allow(carrier).to receive(:each) { |&block| items.each(&block) }
      end

      it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

      context 'when the carrier contains' do
        context 'baggage' do
          let(:value) { 'acme' }
          let(:items) { { key => value } }

          before(:each) do
            items.each do |key, value|
              allow(carrier).to receive(:[]).with(key).and_return(value)
            end
          end

          context 'without a proper prefix' do
            let(:key) { 'HTTP_ACCOUNT_NAME' }
            it { expect(span_context.baggage).to be_empty }
          end

          context 'with a proper prefix' do
            let(:key) { "#{described_class::BAGGAGE_PREFIX_FORMATTED}ACCOUNT_NAME" }
            it { expect(span_context.baggage).to have(1).items }
            it { expect(span_context.baggage).to include('account_name' => value) }
          end
        end
      end
    end
  end
end
