require 'spec_helper'

require 'datadog/tracing/context'
require 'datadog/tracing/trace_operation'
require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::TextMapPropagator do
  describe '#inject' do
    let(:trace_id) { 4363611732769921584 }
    let(:span_id) { 2352279000849524039 }
    let(:sampling_priority) { 1 }
    let(:origin) { 'synthetics' }

    let(:baggage) { { 'account_name' => 'acme' } }

    context 'when given span context with datadog context' do
      let(:span_context) do
        instance_double(
          Datadog::OpenTracer::SpanContext,
          datadog_context: datadog_context,
          baggage: baggage
        )
      end

      let(:datadog_context) do
        instance_double(
          Datadog::Tracing::Context,
          active_trace: datadog_trace
        )
      end

      let(:datadog_trace) do
        Datadog::Tracing::TraceOperation.new(
          id: trace_id,
          parent_span_id: span_id,
          sampling_priority: sampling_priority,
          origin: origin
        )
      end

      it 'sets the carrier correctly' do
        carrier = double.tap { |d| allow(d).to receive(:[]=) }

        described_class.inject(span_context, carrier)

        baggage.each do |key, value|
          expect(carrier).to have_received(:[]=)
            .with(described_class::BAGGAGE_PREFIX + key, value)
        end

        expect(carrier).to have_received(:[]=)
          .with('x-datadog-trace-id', trace_id)
        expect(carrier).to have_received(:[]=)
          .with('x-datadog-parent-id', span_id)
        expect(carrier).to have_received(:[]=)
          .with('x-datadog-sampling-priority', sampling_priority)
        expect(carrier).to have_received(:[]=)
          .with('x-datadog-origin', origin)
      end
    end

    context 'when given span context with datadog trace digest' do
      let(:span_context) do
        instance_double(
          Datadog::OpenTracer::SpanContext,
          datadog_context: nil,
          datadog_trace_digest: datadog_trace_digest,
          baggage: baggage
        )
      end

      let(:datadog_trace_digest) do
        instance_double(
          Datadog::Tracing::TraceDigest,
          span_id: span_id,
          trace_id: trace_id,
          trace_origin: origin,
          trace_sampling_priority: sampling_priority
        )
      end

      it 'sets the carrier correctly' do
        carrier = double.tap { |d| allow(d).to receive(:[]=) }

        described_class.inject(span_context, carrier)

        baggage.each do |key, value|
          expect(carrier).to have_received(:[]=)
            .with(described_class::BAGGAGE_PREFIX + key, value)
        end

        expect(carrier).to have_received(:[]=)
          .with('x-datadog-trace-id', trace_id)
        expect(carrier).to have_received(:[]=)
          .with('x-datadog-parent-id', span_id)
        expect(carrier).to have_received(:[]=)
          .with('x-datadog-sampling-priority', sampling_priority)
        expect(carrier).to have_received(:[]=)
          .with('x-datadog-origin', origin)
      end
    end
  end

  describe '#extract' do
    subject(:span_context) { described_class.extract(carrier) }

    let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }
    let(:items) { {} }
    let(:datadog_context) { span_context.datadog_context }
    let(:datadog_trace_digest) { span_context.datadog_trace_digest }

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
        it { expect(datadog_context).to be nil }
        it { expect(datadog_trace_digest).to be nil }

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

        let(:trace_id) { 123 }
        let(:parent_id) { 456 }
        let(:sampling_priority) { 1 }
        let(:origin) { 'my-origin' }

        it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }
        it { expect(datadog_context).to be nil }
        it { expect(datadog_trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest) }
        it { expect(datadog_trace_digest.span_id).to eq parent_id }
        it { expect(datadog_trace_digest.trace_id).to eq trace_id }
        it { expect(datadog_trace_digest.trace_origin).to eq origin }
        it { expect(datadog_trace_digest.trace_sampling_priority).to eq sampling_priority }

        it_behaves_like 'baggage'
      end
    end
  end
end
