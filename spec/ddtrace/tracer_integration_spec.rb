# typed: false
require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Tracer do
  subject(:tracer) { described_class.new(writer: FauxWriter.new) }

  let(:spans) { tracer.writer.spans(:keep) }

  after do
    tracer.shutdown! # Ensure no state gets left behind
  end

  def sampling_priority_metric(span)
    span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)
  end

  def origin_tag(span)
    span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)
  end

  def lang_tag(span)
    span.get_tag(Datadog::Ext::Runtime::TAG_LANG)
  end

  describe '#active_root_span' do
    subject(:active_root_span) { tracer.active_root_span }

    context 'when a distributed trace is propagated' do
      let(:parent_span_name) { 'operation.parent' }
      let(:child_span_name) { 'operation.child' }

      let(:trace) do
        # Create parent span
        tracer.trace(parent_span_name) do |parent_span_op|
          parent_span_op.context.sampling_priority = Datadog::Ext::Priority::AUTO_KEEP
          parent_span_op.context.origin = 'synthetics'

          # Propagate it via headers
          headers = {}
          Datadog::HTTPPropagator.inject!(parent_span_op.context, headers)
          headers = Hash[headers.map { |k, v| ["http-#{k}".upcase!.tr('-', '_'), v] }]

          # Then extract it from the same headers
          propagated_context = Datadog::HTTPPropagator.extract(headers)
          raise StandardError, 'Failed to propagate trace properly.' unless propagated_context.trace_id

          tracer.provider.context = propagated_context

          # And create child span from propagated context
          tracer.trace(child_span_name) do |_child_span_op|
            @child_root_span = tracer.active_root_span.span
          end
        end
      end

      let(:parent_span) { spans.last }
      let(:child_span) { spans.first }

      context 'by default' do
        before { trace }

        it { expect(spans).to have(2).items }
        it { expect(parent_span.name).to eq(parent_span_name) }
        it { expect(parent_span.finished?).to be(true) }
        it { expect(parent_span.parent_id).to eq(0) }
        it { expect(sampling_priority_metric(parent_span)).to eq(1) }
        it { expect(origin_tag(parent_span)).to eq('synthetics') }
        it { expect(child_span.name).to eq(child_span_name) }
        it { expect(child_span.finished?).to be(true) }
        it { expect(child_span.trace_id).to eq(parent_span.trace_id) }
        it { expect(child_span.parent_id).to eq(parent_span.span_id) }
        it { expect(sampling_priority_metric(child_span)).to eq(1) }
        it { expect(origin_tag(child_span)).to eq('synthetics') }
        # This is expected to be child_span because when propagated, we don't
        # propagate the root span, only its ID. Therefore the span reference
        # should be the first span on the other end of the distributed trace.
        it { expect(@child_root_span).to be child_span }

        it 'does not set runtime metrics language tag' do
          expect(lang_tag(parent_span)).to be nil
          expect(lang_tag(child_span)).to be nil
        end
      end

      context 'when runtime metrics' do
        before do
          allow(Datadog.configuration.runtime_metrics).to receive(:enabled)
            .and_return(enabled)

          allow(Datadog.runtime_metrics).to receive(:associate_with_span)

          trace
        end

        context 'are enabled' do
          let(:enabled) { true }

          it 'associates the span with the runtime' do
            expect(Datadog.runtime_metrics).to have_received(:associate_with_span)
              .with(parent_span)

            expect(Datadog.runtime_metrics).to have_received(:associate_with_span)
              .with(child_span)
          end
        end

        context 'disabled' do
          let(:enabled) { false }

          it 'does not associate the span with the runtime' do
            expect(Datadog.runtime_metrics).to_not have_received(:associate_with_span)
          end
        end
      end
    end
  end

  context 'with synthetics' do
    context 'which applies the context from distributed tracing headers' do
      let(:trace_id) { 3238677264721744442 }
      let(:synthetics_context) { Datadog::HTTPPropagator.extract(distributed_tracing_headers) }
      let(:parent_id) { 0 }
      let(:sampling_priority) { 1 }
      let(:origin) { 'synthetics' }

      let(:distributed_tracing_headers) do
        {
          rack_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID) => trace_id.to_s,
          rack_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID) => parent_id.to_s,
          rack_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY) => sampling_priority.to_s,
          rack_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN) => origin
        }
      end

      def rack_header(header)
        "http-#{header}".upcase!.tr('-', '_')
      end

      before do
        tracer.provider.context = synthetics_context
      end

      shared_examples_for 'a synthetics-sourced trace' do
        before do
          tracer.trace('local.operation') do |local_span_op|
            @local_span = local_span_op.span
            @local_context = tracer.call_context
          end
        end

        it 'that is well-formed' do
          expect(spans).to have(1).item
          expect(spans.first).to be(@local_span)

          spans.first.tap do |local_span|
            expect(local_span.trace_id).to eq(trace_id)
            expect(local_span.parent_id).to eq(parent_id)
            expect(origin_tag(local_span)).to eq(origin)
            expect(sampling_priority_metric(local_span)).to eq(sampling_priority)
          end
        end
      end

      context 'for a synthetics request' do
        let(:origin) { 'synthetics' }

        it_behaves_like 'a synthetics-sourced trace'
      end

      context 'for a synthetics browser request' do
        let(:origin) { 'synthetics-browser' }

        it_behaves_like 'a synthetics-sourced trace'
      end
    end
  end
end
