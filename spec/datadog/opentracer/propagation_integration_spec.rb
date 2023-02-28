require 'spec_helper'

require 'datadog/tracing/utils'
require 'datadog/opentracer'

RSpec.describe 'OpenTracer context propagation' do
  subject(:tracer) { Datadog::OpenTracer::Tracer.new(writer: FauxWriter.new) }

  let(:datadog_tracer) { tracer.datadog_tracer }
  let(:datadog_traces) { datadog_tracer.writer.traces(:keep) }
  let(:datadog_spans) { datadog_tracer.writer.spans(:keep) }

  after do
    # Ensure tracer is shutdown between test, as to not leak threads.
    datadog_tracer.shutdown!
  end

  describe 'via OpenTracing::FORMAT_TEXT_MAP' do
    def baggage_to_carrier_format(baggage)
      baggage.map { |k, v| [Datadog::OpenTracer::TextMapPropagator::BAGGAGE_PREFIX + k, v] }.to_h
    end

    context 'when sending' do
      let(:span_name) { 'operation.sender' }
      let(:baggage) { { 'account_name' => 'acme' } }
      let(:carrier) { {} }

      before do
        tracer.start_active_span(span_name) do |scope|
          scope.span.context.datadog_context.active_trace.sampling_priority = 1
          scope.span.context.datadog_context.active_trace.origin = 'synthetics'
          baggage.each { |k, v| scope.span.set_baggage_item(k, v) }
          tracer.inject(
            scope.span.context,
            OpenTracing::FORMAT_TEXT_MAP,
            carrier
          )
        end
      end

      it do
        expect(carrier).to include(
          'x-datadog-trace-id' => a_kind_of(Integer),
          'x-datadog-parent-id' => a_kind_of(Integer),
          'x-datadog-sampling-priority' => a_kind_of(Integer),
          'x-datadog-origin' => a_kind_of(String)
        )

        expect(carrier['x-datadog-parent-id']).to be > 0

        baggage.each do |k, v|
          expect(carrier).to include(Datadog::OpenTracer::TextMapPropagator::BAGGAGE_PREFIX + k => v)
        end
      end
    end

    context 'when receiving' do
      let(:span_name) { 'operation.receiver' }
      let(:baggage) { { 'account_name' => 'acme' } }
      let(:baggage_with_prefix) { baggage_to_carrier_format(baggage) }
      let(:carrier) { baggage_with_prefix }

      before do
        span_context = tracer.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
        tracer.start_active_span(span_name, child_of: span_context) do |scope|
          @scope = scope
          # Do some work.
        end
      end

      context 'a carrier with valid headers' do
        let(:carrier) do
          super().merge(
            'x-datadog-trace-id' => trace_id.to_s,
            'x-datadog-parent-id' => parent_id.to_s,
            'x-datadog-sampling-priority' => sampling_priority.to_s,
            'x-datadog-origin' => origin.to_s
          )
        end

        let(:trace_id) { Datadog::Tracing::Utils::EXTERNAL_MAX_ID - 1 }
        let(:parent_id) { Datadog::Tracing::Utils::EXTERNAL_MAX_ID - 2 }
        let(:sampling_priority) { 2 }
        let(:origin) { 'synthetics' }

        let(:datadog_trace) { datadog_traces.first }
        let(:datadog_span) { datadog_spans.first }

        it { expect(datadog_trace.sampling_priority).to eq(sampling_priority) }
        it { expect(datadog_trace.origin).to eq(origin) }

        it { expect(datadog_spans).to have(1).items }
        it { expect(datadog_span.name).to eq(span_name) }
        it { expect(datadog_span.finished?).to be(true) }
        it { expect(datadog_span.trace_id).to eq(trace_id) }
        it { expect(datadog_span.parent_id).to eq(parent_id) }
        it { expect(@scope.span.context.baggage).to include(baggage) }
      end

      context 'a carrier with no headers' do
        let(:carrier) { {} }

        let(:datadog_span) { datadog_spans.first }

        it { expect(datadog_spans).to have(1).items }
        it { expect(datadog_span.name).to eq(span_name) }
        it { expect(datadog_span.finished?).to be(true) }
        it { expect(datadog_span.parent_id).to eq(0) }
      end
    end

    context 'in a round-trip' do
      let(:origin_span_name) { 'operation.origin' }
      let(:origin_datadog_trace) { datadog_traces.find { |x| x.name == origin_span_name } }
      let(:origin_datadog_span) { datadog_spans.find { |x| x.name == origin_span_name } }

      let(:intermediate_span_name) { 'operation.intermediate' }
      let(:intermediate_datadog_trace) { datadog_traces.find { |x| x.name == intermediate_span_name } }
      let(:intermediate_datadog_span) { datadog_spans.find { |x| x.name == intermediate_span_name } }

      let(:destination_span_name) { 'operation.destination' }
      let(:destination_datadog_trace) { datadog_traces.find { |x| x.name == destination_span_name } }
      let(:destination_datadog_span) { datadog_spans.find { |x| x.name == destination_span_name } }

      let(:baggage) { { 'account_name' => 'acme' } }

      before do
        tracer.start_active_span(origin_span_name) do |origin_scope|
          origin_datadog_context = origin_scope.span.context.datadog_context
          origin_datadog_context.active_trace.sampling_priority = 1
          origin_datadog_context.active_trace.origin = 'synthetics'
          baggage.each { |k, v| origin_scope.span.set_baggage_item(k, v) }

          @origin_carrier = {}.tap do |c|
            tracer.inject(origin_scope.span.context, OpenTracing::FORMAT_TEXT_MAP, c)
          end
          origin_datadog_context.activate!(nil) do
            tracer.start_active_span(
              intermediate_span_name,
              child_of: tracer.extract(OpenTracing::FORMAT_TEXT_MAP, @origin_carrier)
            ) do |intermediate_scope|
              @intermediate_scope = intermediate_scope

              @intermediate_carrier = {}.tap do |c|
                tracer.inject(intermediate_scope.span.context, OpenTracing::FORMAT_TEXT_MAP, c)
              end

              tracer.start_active_span(
                destination_span_name,
                child_of: tracer.extract(OpenTracing::FORMAT_TEXT_MAP, @intermediate_carrier)
              ) do |destination_scope|
                @destination_scope = destination_scope
                # Do something
              end
            end
          end
        end
      end

      it { expect(datadog_traces).to have(3).items }
      it { expect(datadog_spans).to have(3).items }

      it { expect(origin_datadog_trace.sampling_priority).to eq(1) }
      it { expect(origin_datadog_trace.origin).to eq('synthetics') }
      it { expect(origin_datadog_span.finished?).to be(true) }
      it { expect(origin_datadog_span.parent_id).to eq(0) }

      it { expect(intermediate_datadog_trace.sampling_priority).to eq(1) }
      it { expect(intermediate_datadog_trace.origin).to eq('synthetics') }
      it { expect(intermediate_datadog_span.finished?).to be(true) }
      it { expect(intermediate_datadog_span.trace_id).to eq(origin_datadog_span.trace_id) }
      it { expect(intermediate_datadog_span.parent_id).to eq(origin_datadog_span.span_id) }
      it { expect(@intermediate_scope.span.context.baggage).to include(baggage) }

      it { expect(destination_datadog_trace.sampling_priority).to eq(1) }
      it { expect(destination_datadog_trace.origin).to eq('synthetics') }
      it { expect(destination_datadog_span.finished?).to be(true) }
      it { expect(destination_datadog_span.trace_id).to eq(intermediate_datadog_span.trace_id) }
      it { expect(destination_datadog_span.parent_id).to eq(intermediate_datadog_span.span_id) }
      it { expect(@destination_scope.span.context.baggage).to include(baggage) }

      it do
        expect(@origin_carrier).to include(
          'x-datadog-trace-id' => origin_datadog_span.trace_id,
          'x-datadog-parent-id' => origin_datadog_span.span_id,
          'x-datadog-sampling-priority' => 1,
          'x-datadog-origin' => 'synthetics',
          'ot-baggage-account_name' => 'acme'
        )
      end

      it do
        expect(@intermediate_carrier).to include(
          'x-datadog-trace-id' => intermediate_datadog_span.trace_id,
          'x-datadog-parent-id' => intermediate_datadog_span.span_id,
          'x-datadog-sampling-priority' => 1,
          'x-datadog-origin' => 'synthetics',
          'ot-baggage-account_name' => 'acme'
        )
      end
    end
  end

  describe 'via OpenTracing::FORMAT_RACK' do
    def carrier_to_rack_format(carrier)
      carrier.map { |k, v| [RackSupport.header_to_rack(k), v] }.to_h
    end

    def baggage_to_carrier_format(baggage)
      baggage.map { |k, v| [Datadog::OpenTracer::RackPropagator::BAGGAGE_PREFIX + k, v] }.to_h
    end

    context 'when sending' do
      let(:span_name) { 'operation.sender' }
      let(:baggage) { { 'account_name' => 'acme' } }
      let(:carrier) { {} }

      before do
        tracer.start_active_span(span_name) do |scope|
          scope.span.context.datadog_context.active_trace.sampling_priority = 1
          scope.span.context.datadog_context.active_trace.origin = 'synthetics'
          baggage.each { |k, v| scope.span.set_baggage_item(k, v) }
          tracer.inject(
            scope.span.context,
            OpenTracing::FORMAT_RACK,
            carrier
          )
        end
      end

      it do
        expect(carrier).to include(
          'x-datadog-trace-id' => a_kind_of(String),
          'x-datadog-parent-id' => a_kind_of(String),
          'x-datadog-sampling-priority' => a_kind_of(String),
          'x-datadog-origin' => a_kind_of(String)
        )

        expect(carrier['x-datadog-parent-id'].to_i).to be > 0

        baggage.each do |k, v|
          expect(carrier).to include(Datadog::OpenTracer::RackPropagator::BAGGAGE_PREFIX + k => v)
        end
      end
    end

    context 'when receiving' do
      let(:span_name) { 'operation.receiver' }
      let(:baggage) { { 'account_name' => 'acme' } }
      let(:baggage_with_prefix) { baggage_to_carrier_format(baggage) }
      let(:carrier) { carrier_to_rack_format(baggage_with_prefix) }

      before do
        span_context = tracer.extract(OpenTracing::FORMAT_RACK, carrier)
        tracer.start_active_span(span_name, child_of: span_context) do |scope|
          @scope = scope
          # Do some work.
        end
      end

      context 'a carrier with valid headers' do
        let(:carrier) do
          super().merge(
            carrier_to_rack_format(
              'x-datadog-trace-id' => trace_id.to_s,
              'x-datadog-parent-id' => parent_id.to_s,
              'x-datadog-sampling-priority' => sampling_priority.to_s,
              'x-datadog-origin' => origin.to_s
            )
          )
        end

        let(:trace_id) { Datadog::Tracing::Utils::EXTERNAL_MAX_ID - 1 }
        let(:parent_id) { Datadog::Tracing::Utils::EXTERNAL_MAX_ID - 2 }
        let(:sampling_priority) { 2 }
        let(:origin) { 'synthetics' }

        let(:datadog_span) { datadog_spans.first }
        let(:datadog_trace) { datadog_traces.first }

        it { expect(datadog_trace.sampling_priority).to eq(sampling_priority) }
        it { expect(datadog_trace.origin).to eq('synthetics') }

        it { expect(datadog_spans).to have(1).items }
        it { expect(datadog_span.name).to eq(span_name) }
        it { expect(datadog_span.finished?).to be(true) }
        it { expect(datadog_span.trace_id).to eq(trace_id) }
        it { expect(datadog_span.parent_id).to eq(parent_id) }
        it { expect(@scope.span.context.baggage).to include(baggage) }
      end

      context 'a carrier with no headers' do
        let(:carrier) { {} }

        let(:datadog_span) { datadog_spans.first }

        it { expect(datadog_spans).to have(1).items }
        it { expect(datadog_span.name).to eq(span_name) }
        it { expect(datadog_span.finished?).to be(true) }
        it { expect(datadog_span.parent_id).to eq(0) }
      end
    end

    context 'in a round-trip' do
      let(:origin_span_name) { 'operation.origin' }
      let(:origin_datadog_trace) { datadog_traces.find { |x| x.name == origin_span_name } }
      let(:origin_datadog_span) { datadog_spans.find { |x| x.name == origin_span_name } }

      let(:intermediate_span_name) { 'operation.intermediate' }
      let(:intermediate_datadog_trace) { datadog_traces.find { |x| x.name == intermediate_span_name } }
      let(:intermediate_datadog_span) { datadog_spans.find { |x| x.name == intermediate_span_name } }

      let(:destination_span_name) { 'operation.destination' }
      let(:destination_datadog_trace) { datadog_traces.find { |x| x.name == destination_span_name } }
      let(:destination_datadog_span) { datadog_spans.find { |x| x.name == destination_span_name } }

      # NOTE: If these baggage names include either dashes or uppercase characters
      #       they will not make a round-trip with the same key format. They will
      #       be converted to underscores and lowercase characters, because Rack
      #       forces everything to uppercase/dashes in transport causing resolution
      #       on key format to be lost.
      let(:baggage) { { 'account_name' => 'acme' } }

      before do
        tracer.start_active_span(origin_span_name) do |origin_scope|
          origin_datadog_context = origin_scope.span.context.datadog_context
          origin_datadog_context.active_trace.sampling_priority = 1
          origin_datadog_context.active_trace.origin = 'synthetics'

          baggage.each { |k, v| origin_scope.span.set_baggage_item(k, v) }

          @origin_carrier = {}.tap do |c|
            tracer.inject(origin_scope.span.context, OpenTracing::FORMAT_RACK, c)
          end

          origin_datadog_context.activate!(nil) do
            tracer.start_active_span(
              intermediate_span_name,
              child_of: tracer.extract(OpenTracing::FORMAT_RACK, carrier_to_rack_format(@origin_carrier))
            ) do |intermediate_scope|
              @intermediate_scope = intermediate_scope

              @intermediate_carrier = {}.tap do |c|
                tracer.inject(intermediate_scope.span.context, OpenTracing::FORMAT_RACK, c)
              end

              tracer.start_active_span(
                destination_span_name,
                child_of: tracer.extract(OpenTracing::FORMAT_RACK, carrier_to_rack_format(@intermediate_carrier))
              ) do |destination_scope|
                @destination_scope = destination_scope
                # Do something
              end
            end
          end
        end
      end

      it { expect(datadog_traces).to have(3).items }
      it { expect(datadog_spans).to have(3).items }

      it { expect(origin_datadog_trace.sampling_priority).to eq(1) }
      it { expect(origin_datadog_span.finished?).to be(true) }
      it { expect(origin_datadog_span.parent_id).to eq(0) }

      it { expect(intermediate_datadog_trace.sampling_priority).to eq(1) }
      it { expect(intermediate_datadog_span.finished?).to be(true) }
      it { expect(intermediate_datadog_span.trace_id).to eq(origin_datadog_span.trace_id) }
      it { expect(intermediate_datadog_span.parent_id).to eq(origin_datadog_span.span_id) }
      it { expect(@intermediate_scope.span.context.baggage).to include(baggage) }

      it { expect(destination_datadog_trace.sampling_priority).to eq(1) }
      it { expect(destination_datadog_span.finished?).to be(true) }
      it { expect(destination_datadog_span.trace_id).to eq(intermediate_datadog_span.trace_id) }
      it { expect(destination_datadog_span.parent_id).to eq(intermediate_datadog_span.span_id) }
      it { expect(@destination_scope.span.context.baggage).to include(baggage) }

      it do
        expect(@origin_carrier).to include(
          'x-datadog-trace-id' => origin_datadog_span.trace_id.to_s,
          'x-datadog-parent-id' => origin_datadog_span.span_id.to_s,
          'x-datadog-sampling-priority' => '1',
          'x-datadog-origin' => 'synthetics',
          'ot-baggage-account_name' => 'acme'
        )
      end

      it do
        expect(@intermediate_carrier).to include(
          'x-datadog-trace-id' => intermediate_datadog_span.trace_id.to_s,
          'x-datadog-parent-id' => intermediate_datadog_span.span_id.to_s,
          'x-datadog-sampling-priority' => '1',
          'x-datadog-origin' => 'synthetics',
          'ot-baggage-account_name' => 'acme'
        )
      end
    end
  end
end
