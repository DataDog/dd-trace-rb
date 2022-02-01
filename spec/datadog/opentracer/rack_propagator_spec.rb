# typed: ignore
require 'spec_helper'

require 'datadog/tracing/context'
require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/propagation/http'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/trace_operation'
require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::RackPropagator do
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

    let(:trace_id) { double('trace ID') }
    let(:span_id) { double('span ID') }
    let(:sampling_priority) { double('sampling priority') }
    let(:origin) { double('synthetics') }

    let(:baggage) { { 'account_name' => 'acme' } }

    let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }

    # Expect carrier to be set with Datadog trace properties
    before do
      expect(carrier).to receive(:[]=)
        .with(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID, trace_id.to_s)
      expect(carrier).to receive(:[]=)
        .with(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID, span_id.to_s)
      expect(carrier).to receive(:[]=)
        .with(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_SAMPLING_PRIORITY, sampling_priority.to_s)
      expect(carrier).to receive(:[]=)
        .with(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_ORIGIN, origin.to_s)
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
    let(:datadog_trace_digest) do
      instance_double(
        Datadog::Tracing::TraceDigest,
        span_id: double('span ID'),
        trace_id: double('trace ID'),
        trace_origin: double('origin'),
        trace_sampling_priority: double('sampling priority')
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
