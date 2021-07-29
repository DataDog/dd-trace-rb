require 'spec_helper'

require 'ddtrace/opentracer'

RSpec.describe Datadog::OpenTracer::TextMapPropagator do
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
        sampling_priority: sampling_priority,
        origin: origin
      )
    end

    let(:trace_id) { double('trace ID') }
    let(:span_id) { double('span ID') }
    let(:sampling_priority) { double('sampling priority') }
    let(:origin) { double('synthetics') }

    let(:baggage) { { 'account_name' => 'acme' } }

    let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }

    # Expect carrier to be set with Datadog trace properties
    before do
      expect(carrier).to receive(:[]=)
        .with(Datadog::OpenTracer::DistributedHeaders::HTTP_HEADER_TRACE_ID, trace_id)
      expect(carrier).to receive(:[]=)
        .with(Datadog::OpenTracer::DistributedHeaders::HTTP_HEADER_PARENT_ID, span_id)
      expect(carrier).to receive(:[]=)
        .with(Datadog::OpenTracer::DistributedHeaders::HTTP_HEADER_SAMPLING_PRIORITY, sampling_priority)
      expect(carrier).to receive(:[]=)
        .with(Datadog::OpenTracer::DistributedHeaders::HTTP_HEADER_ORIGIN, origin)
    end

    # Expect carrier to be set with OpenTracing baggage
    before do
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
    let(:datadog_context) { span_context.datadog_context }

    before do
      allow(carrier).to receive(:each) { |&block| items.each(&block) }
    end

    context 'when the carrier contains' do
      before do
        allow(Datadog::OpenTracer::DistributedHeaders).to receive(:new)
          .with(carrier)
          .and_return(headers)
      end

      shared_examples_for 'baggage' do
        let(:value) { 'acme' }
        let(:items) { { key => value } }

        context 'with a symbol' do
          context 'that does not have a proper prefix' do
            let(:key) { :my_baggage_item }

            it { expect(span_context.baggage).to be_empty }
          end

          context 'that has a proper prefix' do
            let(:key) { :"#{described_class::BAGGAGE_PREFIX}account_name" }

            it { expect(span_context.baggage).to have(1).items }
            it { expect(span_context.baggage).to include('account_name' => value) }
          end
        end

        context 'with a string' do
          context 'that does not have a proper prefix' do
            let(:key) { 'HTTP_ACCOUNT_NAME' }

            it { expect(span_context.baggage).to be_empty }
          end

          context 'that has a proper prefix' do
            let(:key) { "#{described_class::BAGGAGE_PREFIX}account_name" }

            it { expect(span_context.baggage).to have(1).items }
            it { expect(span_context.baggage).to include('account_name' => value) }
          end
        end
      end

      context 'invalid Datadog headers' do
        let(:headers) do
          instance_double(
            Datadog::OpenTracer::DistributedHeaders,
            valid?: false
          )
        end

        it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }
        it { expect(datadog_context.trace_id).to be nil }
        it { expect(datadog_context.span_id).to be nil }
        it { expect(datadog_context.sampling_priority).to be nil }
        it { expect(datadog_context.origin).to be nil }

        it_behaves_like 'baggage'
      end

      context 'valid Datadog headers' do
        let(:headers) do
          instance_double(
            Datadog::OpenTracer::DistributedHeaders,
            valid?: true,
            trace_id: trace_id,
            parent_id: parent_id,
            sampling_priority: sampling_priority,
            origin: origin
          )
        end

        let(:trace_id) { double('trace ID') }
        let(:parent_id) { double('parent span ID') }
        let(:sampling_priority) { double('sampling priority') }
        let(:origin) { double('synthetics') }

        it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }
        it { expect(datadog_context.trace_id).to be trace_id }
        it { expect(datadog_context.span_id).to be parent_id }
        it { expect(datadog_context.sampling_priority).to be sampling_priority }
        it { expect(datadog_context.origin).to be origin }

        it_behaves_like 'baggage'
      end
    end
  end
end
