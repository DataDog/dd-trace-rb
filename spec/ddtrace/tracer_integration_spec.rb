require 'spec_helper'

require 'ddtrace'
require 'ddtrace/ext/runtime'
require 'ddtrace/runtime/identity'
require 'ddtrace/propagation/http_propagator'

RSpec.describe Datadog::Tracer do
  subject(:tracer) { described_class.new(writer: FauxWriter.new) }
  let(:spans) { tracer.writer.spans(:keep) }

  def sampling_priority_metric(span)
    span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)
  end

  def origin_tag(span)
    span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)
  end

  def lang_tag(span)
    span.get_tag(Datadog::Ext::Runtime::TAG_LANG)
  end

  def runtime_id_tag(span)
    span.get_tag(Datadog::Ext::Runtime::TAG_RUNTIME_ID)
  end

  describe '#active_root_span' do
    subject(:active_root_span) { tracer.active_root_span }

    context 'when a distributed trace is propagated' do
      let(:parent_span_name) { 'operation.parent' }
      let(:child_span_name) { 'operation.child' }

      before(:each) do
        # Create parent span
        tracer.trace(parent_span_name) do |parent_span|
          @parent_span = parent_span
          parent_span.context.sampling_priority = Datadog::Ext::Priority::AUTO_KEEP
          parent_span.context.origin = 'synthetics'

          # Propagate it via headers
          headers = {}
          Datadog::HTTPPropagator.inject!(parent_span.context, headers)
          headers = Hash[headers.map { |k, v| ["http-#{k}".upcase!.tr('-', '_'), v] }]

          # Then extract it from the same headers
          propagated_context = Datadog::HTTPPropagator.extract(headers)
          raise StandardError, 'Failed to propagate trace properly.' unless propagated_context.trace_id
          tracer.provider.context = propagated_context

          # And create child span from propagated context
          tracer.trace(child_span_name) do |child_span|
            @child_span = child_span
            @child_root_span = tracer.active_root_span
          end
        end
      end

      let(:parent_span) { spans.last }
      let(:child_span) { spans.first }

      it { expect(spans).to have(2).items }
      it { expect(parent_span.name).to eq(parent_span_name) }
      it { expect(parent_span.finished?).to be(true) }
      it { expect(parent_span.parent_id).to eq(0) }
      it { expect(sampling_priority_metric(parent_span)).to eq(1) }
      it { expect(origin_tag(parent_span)).to eq('synthetics') }
      it { expect(lang_tag(parent_span)).to eq('ruby') }
      it { expect(runtime_id_tag(parent_span)).to eq(Datadog::Runtime::Identity.id) }
      it { expect(child_span.name).to eq(child_span_name) }
      it { expect(child_span.finished?).to be(true) }
      it { expect(child_span.trace_id).to eq(parent_span.trace_id) }
      it { expect(child_span.parent_id).to eq(parent_span.span_id) }
      it { expect(sampling_priority_metric(child_span)).to eq(1) }
      it { expect(origin_tag(child_span)).to eq('synthetics') }
      it { expect(lang_tag(child_span)).to eq('ruby') }
      it { expect(runtime_id_tag(child_span)).to eq(Datadog::Runtime::Identity.id) }
      # This is expected to be child_span because when propagated, we don't
      # propagate the root span, only its ID. Therefore the span reference
      # should be the first span on the other end of the distributed trace.
      it { expect(@child_root_span).to be child_span }
    end
  end
end
