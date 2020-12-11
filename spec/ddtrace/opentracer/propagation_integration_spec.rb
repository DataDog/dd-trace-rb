require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe 'OpenTracer context propagation' do
    include_context 'OpenTracing helpers'

    subject(:tracer) { Datadog::OpenTracer::Tracer.new(writer: FauxWriter.new) }
    let(:datadog_tracer) { tracer.datadog_tracer }
    let(:datadog_spans) { datadog_tracer.writer.spans(:keep) }

    after do
      # Ensure tracer is shutdown between test, as to not leak threads.
      datadog_tracer.shutdown!
    end

    def sampling_priority_metric(span)
      span.get_metric(Datadog::OpenTracer::TextMapPropagator::SAMPLING_PRIORITY_KEY)
    end

    def origin_tag(span)
      span.get_tag(Datadog::OpenTracer::TextMapPropagator::ORIGIN_KEY)
    end

    describe 'via OpenTracing::FORMAT_TEXT_MAP' do
      def baggage_to_carrier_format(baggage)
        baggage.map { |k, v| [Datadog::OpenTracer::TextMapPropagator::BAGGAGE_PREFIX + k, v] }.to_h
      end

      context 'when sending' do
        let(:span_name) { 'operation.sender' }
        let(:baggage) { { 'account_name' => 'acme' } }
        let(:carrier) { {} }

        before(:each) do
          tracer.start_active_span(span_name) do |scope|
            scope.span.context.datadog_context.sampling_priority = 1
            scope.span.context.datadog_context.origin = 'synthetics'
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
            Datadog::OpenTracer::TextMapPropagator::HTTP_HEADER_TRACE_ID => a_kind_of(Integer),
            Datadog::OpenTracer::TextMapPropagator::HTTP_HEADER_PARENT_ID => a_kind_of(Integer),
            Datadog::OpenTracer::TextMapPropagator::HTTP_HEADER_SAMPLING_PRIORITY => a_kind_of(Integer),
            Datadog::OpenTracer::TextMapPropagator::HTTP_HEADER_ORIGIN => a_kind_of(String)
          )

          expect(carrier[Datadog::OpenTracer::TextMapPropagator::HTTP_HEADER_PARENT_ID]).to be > 0

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

        before(:each) do
          span_context = tracer.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
          tracer.start_active_span(span_name, child_of: span_context) do |scope|
            @scope = scope
            # Do some work.
          end
        end

        context 'a carrier with valid headers' do
          let(:carrier) do
            super().merge(
              Datadog::OpenTracer::TextMapPropagator::HTTP_HEADER_TRACE_ID => trace_id.to_s,
              Datadog::OpenTracer::TextMapPropagator::HTTP_HEADER_PARENT_ID => parent_id.to_s,
              Datadog::OpenTracer::TextMapPropagator::HTTP_HEADER_SAMPLING_PRIORITY => sampling_priority.to_s,
              Datadog::OpenTracer::TextMapPropagator::HTTP_HEADER_ORIGIN => origin.to_s
            )
          end

          let(:trace_id) { Datadog::Span::EXTERNAL_MAX_ID - 1 }
          let(:parent_id) { Datadog::Span::EXTERNAL_MAX_ID - 2 }
          let(:sampling_priority) { 2 }
          let(:origin) { 'synthetics' }

          let(:datadog_span) { datadog_spans.first }

          it { expect(datadog_spans).to have(1).items }
          it { expect(datadog_span.name).to eq(span_name) }
          it { expect(datadog_span.finished?).to be(true) }
          it { expect(datadog_span.trace_id).to eq(trace_id) }
          it { expect(datadog_span.parent_id).to eq(parent_id) }
          it { expect(sampling_priority_metric(datadog_span)).to eq(sampling_priority) }
          it { expect(origin_tag(datadog_span)).to eq(origin) }
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
        let(:sender_span_name) { 'operation.sender' }
        let(:receiver_span_name) { 'operation.receiver' }
        let(:baggage) { { 'account_name' => 'acme' } }
        let(:carrier) { {} }

        before(:each) do
          tracer.start_active_span(sender_span_name) do |sender_scope|
            sender_scope.span.context.datadog_context.sampling_priority = 1
            sender_scope.span.context.datadog_context.origin = 'synthetics'
            baggage.each { |k, v| sender_scope.span.set_baggage_item(k, v) }
            tracer.inject(
              sender_scope.span.context,
              OpenTracing::FORMAT_TEXT_MAP,
              carrier
            )

            span_context = tracer.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
            tracer.start_active_span(receiver_span_name, child_of: span_context) do |receiver_scope|
              @receiver_scope = receiver_scope
              # Do some work.
            end
          end
        end

        let(:sender_datadog_span) { datadog_spans.last }
        let(:receiver_datadog_span) { datadog_spans.first }

        it { expect(datadog_spans).to have(2).items }
        it { expect(sender_datadog_span.name).to eq(sender_span_name) }
        it { expect(sender_datadog_span.finished?).to be(true) }
        it { expect(sender_datadog_span.parent_id).to eq(0) }
        it { expect(sampling_priority_metric(sender_datadog_span)).to eq(1) }
        it { expect(origin_tag(sender_datadog_span)).to eq('synthetics') }
        it { expect(receiver_datadog_span.name).to eq(receiver_span_name) }
        it { expect(receiver_datadog_span.finished?).to be(true) }
        it { expect(receiver_datadog_span.trace_id).to eq(sender_datadog_span.trace_id) }
        it { expect(receiver_datadog_span.parent_id).to eq(sender_datadog_span.span_id) }
        it { expect(sampling_priority_metric(receiver_datadog_span)).to eq(1) }
        it { expect(origin_tag(receiver_datadog_span)).to eq('synthetics') }
        it { expect(@receiver_scope.span.context.baggage).to include(baggage) }
      end
    end

    describe 'via OpenTracing::FORMAT_RACK' do
      def carrier_to_rack_format(carrier)
        carrier.map { |k, v| ["http-#{k}".upcase!.tr('-', '_'), v] }.to_h
      end

      def baggage_to_carrier_format(baggage)
        baggage.map { |k, v| [Datadog::OpenTracer::RackPropagator::BAGGAGE_PREFIX + k, v] }.to_h
      end

      context 'when sending' do
        let(:span_name) { 'operation.sender' }
        let(:baggage) { { 'account_name' => 'acme' } }
        let(:carrier) { {} }

        before(:each) do
          tracer.start_active_span(span_name) do |scope|
            scope.span.context.datadog_context.sampling_priority = 1
            scope.span.context.datadog_context.origin = 'synthetics'
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
            Datadog::OpenTracer::RackPropagator::HTTP_HEADER_TRACE_ID => a_kind_of(String),
            Datadog::OpenTracer::RackPropagator::HTTP_HEADER_PARENT_ID => a_kind_of(String),
            Datadog::OpenTracer::RackPropagator::HTTP_HEADER_SAMPLING_PRIORITY => a_kind_of(String),
            Datadog::OpenTracer::RackPropagator::HTTP_HEADER_ORIGIN => a_kind_of(String)
          )

          expect(carrier[Datadog::OpenTracer::RackPropagator::HTTP_HEADER_PARENT_ID].to_i).to be > 0

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

        before(:each) do
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
                Datadog::OpenTracer::RackPropagator::HTTP_HEADER_TRACE_ID => trace_id.to_s,
                Datadog::OpenTracer::RackPropagator::HTTP_HEADER_PARENT_ID => parent_id.to_s,
                Datadog::OpenTracer::RackPropagator::HTTP_HEADER_SAMPLING_PRIORITY => sampling_priority.to_s,
                Datadog::OpenTracer::RackPropagator::HTTP_HEADER_ORIGIN => origin.to_s
              )
            )
          end

          let(:trace_id) { Datadog::Span::EXTERNAL_MAX_ID - 1 }
          let(:parent_id) { Datadog::Span::EXTERNAL_MAX_ID - 2 }
          let(:sampling_priority) { 2 }
          let(:origin) { 'synthetics' }

          let(:datadog_span) { datadog_spans.first }

          it { expect(datadog_spans).to have(1).items }
          it { expect(datadog_span.name).to eq(span_name) }
          it { expect(datadog_span.finished?).to be(true) }
          it { expect(datadog_span.trace_id).to eq(trace_id) }
          it { expect(datadog_span.parent_id).to eq(parent_id) }
          it { expect(sampling_priority_metric(datadog_span)).to eq(sampling_priority) }
          it { expect(origin_tag(datadog_span)).to eq('synthetics') }
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
        let(:sender_span_name) { 'operation.sender' }
        let(:receiver_span_name) { 'operation.receiver' }
        # NOTE: If these baggage names include either dashes or uppercase characters
        #       they will not make a round-trip with the same key format. They will
        #       be converted to underscores and lowercase characters, because Rack
        #       forces everything to uppercase/dashes in transport causing resolution
        #       on key format to be lost.
        let(:baggage) { { 'account_name' => 'acme' } }

        before(:each) do
          tracer.start_active_span(sender_span_name) do |sender_scope|
            sender_scope.span.context.datadog_context.sampling_priority = 1
            sender_scope.span.context.datadog_context.origin = 'synthetics'
            baggage.each { |k, v| sender_scope.span.set_baggage_item(k, v) }

            carrier = {}
            tracer.inject(
              sender_scope.span.context,
              OpenTracing::FORMAT_RACK,
              carrier
            )

            carrier = carrier_to_rack_format(carrier)

            span_context = tracer.extract(OpenTracing::FORMAT_RACK, carrier)
            tracer.start_active_span(receiver_span_name, child_of: span_context) do |receiver_scope|
              @receiver_scope = receiver_scope
              # Do some work.
            end
          end
        end

        let(:sender_datadog_span) { datadog_spans.last }
        let(:receiver_datadog_span) { datadog_spans.first }

        it { expect(datadog_spans).to have(2).items }
        it { expect(sender_datadog_span.name).to eq(sender_span_name) }
        it { expect(sender_datadog_span.finished?).to be(true) }
        it { expect(sender_datadog_span.parent_id).to eq(0) }
        it { expect(sampling_priority_metric(sender_datadog_span)).to eq(1) }
        it { expect(receiver_datadog_span.name).to eq(receiver_span_name) }
        it { expect(receiver_datadog_span.finished?).to be(true) }
        it { expect(receiver_datadog_span.trace_id).to eq(sender_datadog_span.trace_id) }
        it { expect(receiver_datadog_span.parent_id).to eq(sender_datadog_span.span_id) }
        it { expect(sampling_priority_metric(receiver_datadog_span)).to eq(1) }
        it { expect(@receiver_scope.span.context.baggage).to include(baggage) }
      end
    end
  end
end
