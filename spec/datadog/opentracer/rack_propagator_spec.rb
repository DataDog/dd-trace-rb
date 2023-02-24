require 'spec_helper'

require 'datadog/tracing/context'
require 'datadog/tracing/propagation/http'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/trace_operation'
require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::RackPropagator do
  describe '#inject' do
    subject { described_class.inject(span_context, carrier) }

    let(:trace_id) { double('trace ID') }
    let(:span_id) { double('span ID') }
    let(:sampling_decision) { '-1' }
    let(:sampling_priority) { double('sampling priority') }
    let(:origin) { double('synthetics') }
    let(:trace_distributed_tags) { { '_dd.p.key' => 'value', '_dd.p.dm' => sampling_decision } }

    let(:baggage) { { 'account_name' => 'acme' } }

    let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }

    before do
      # Expect carrier to be set with Datadog trace properties
      expect(carrier).to receive(:[]=)
        .with('x-datadog-trace-id', trace_id.to_s)
      expect(carrier).to receive(:[]=)
        .with('x-datadog-parent-id', span_id.to_s)
      expect(carrier).to receive(:[]=)
        .with('x-datadog-sampling-priority', sampling_priority.to_s)
      expect(carrier).to receive(:[]=)
        .with('x-datadog-origin', origin.to_s)
      expect(carrier).to receive(:[]=)
        .with('x-datadog-tags', '_dd.p.key=value,_dd.p.dm=-1')

      # Expect carrier to be set with OpenTracing baggage
      baggage.each do |key, value|
        expect(carrier).to receive(:[]=)
          .with(described_class::BAGGAGE_PREFIX + key, value)
      end
    end

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
          origin: origin,
          tags: trace_distributed_tags
        )
      end

      it { is_expected.to be nil }
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
          trace_sampling_priority: sampling_priority,
          trace_distributed_tags: trace_distributed_tags,
        )
      end
      it { is_expected.to be nil }
    end
  end

  describe '#extract' do
    subject(:span_context) { described_class.extract(carrier) }

    let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }
    let(:items) { {} }
    let(:datadog_trace_digest) do
      instance_double(
        Datadog::Tracing::TraceDigest,
        span_id: double('span ID'),
        trace_id: double('trace ID'),
        trace_origin: double('origin'),
        trace_sampling_priority: double('sampling priority'),
        trace_distributed_tags: double('trace_distributed_tags'),
      )
    end

    before do
      expect(Datadog::Tracing::Propagation::HTTP).to receive(:extract)
        .with(carrier)
        .and_return(datadog_trace_digest)

      allow(carrier).to receive(:each) { |&block| items.each(&block) }
    end

    it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

    context 'when the carrier contains' do
      context 'baggage' do
        let(:value) { 'acme' }
        let(:items) { { key => value } }

        before do
          items.each do |key, value|
            allow(carrier).to receive(:[]).with(key).and_return(value)
          end
        end

        context 'with a symbol' do
          context 'that does not have a proper prefix' do
            let(:key) { :my_baggage_item }

            it { expect(span_context.baggage).to be_empty }
          end

          context 'that has a proper prefix' do
            let(:key) { :"#{described_class::BAGGAGE_PREFIX_FORMATTED}ACCOUNT_NAME" }

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
            let(:key) { "#{described_class::BAGGAGE_PREFIX_FORMATTED}ACCOUNT_NAME" }

            it { expect(span_context.baggage).to have(1).items }
            it { expect(span_context.baggage).to include('account_name' => value) }
          end
        end
      end
    end
  end
end
