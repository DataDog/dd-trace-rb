require 'spec_helper'
require 'opentelemetry/sdk'
require 'datadog/opentelemetry'

RSpec.describe Datadog::OpenTelemetry do
  context 'with Datadog TraceProvider' do
    let(:otel_tracer) { OpenTelemetry.tracer_provider.tracer('otel-tracer') }
    let(:writer) { get_test_writer }
    let(:tracer) { Datadog::Tracing.send(:tracer) }
    let(:otel_root_parent) { OpenTelemetry::Trace::INVALID_SPAN_ID }

    before do
      writer_ = writer
      Datadog.configure do |c|
        c.tracing.writer = writer_
        c.tracing.partial_flush.min_spans_threshold = 1 # Ensure tests flush spans quickly
      end

      ::OpenTelemetry::SDK.configure do |c|
      end
    end

    after do
      ::OpenTelemetry.logger = nil
    end

    it 'returns the same tracer on successive calls' do
      expect(otel_tracer).to be(OpenTelemetry.tracer_provider.tracer('otel-tracer'))
    end

    shared_context 'parent and child spans' do
      let(:parent) { spans.find { |s| s.parent_id == 0 } }
      let(:child) { spans.find { |s| s != parent } }

      it { expect(spans).to have(2).items }

      it 'have child-parent relationship' do
        expect(parent).to be_root_span
        expect(child.parent_id).to eq(parent.id)
      end
    end

    describe '#in_span' do
      context 'without an active span' do
        subject!(:in_span) { otel_tracer.in_span('test') {} }

        it 'records a finished span' do
          expect(span).to be_root_span
          expect(span.name).to eq('test')
          expect(span.resource).to eq('test')
          expect(span.service).to eq(tracer.default_service)
        end
      end

      context 'with an active span' do
        subject!(:in_span) do
          otel_tracer.in_span('otel-parent') do
            otel_tracer.in_span('otel-child') {}
          end
        end

        include_context 'parent and child spans'

        it 'sets parent to active span' do
          expect(parent.name).to eq('otel-parent')
          expect(child.name).to eq('otel-child')
        end
      end

      context 'with an active Datadog span' do
        subject!(:in_span) do
          tracer.trace('datadog-parent') do
            otel_tracer.in_span('otel-child') {}
          end
        end

        include_context 'parent and child spans'

        it 'sets parent to active span' do
          expect(parent.name).to eq('datadog-parent')
          expect(child.name).to eq('otel-child')
        end
      end

      context 'with a Datadog child span' do
        subject!(:in_span) do
          otel_tracer.in_span('otel-parent') do
            tracer.trace('datadog-child') {}
          end
        end

        include_context 'parent and child spans'

        it 'attaches Datadog span as a child' do
          expect(parent.name).to eq('otel-parent')
          expect(child.name).to eq('datadog-child')
        end
      end
    end

    describe '#start_span' do
      subject(:start_span) { otel_tracer.start_span('start-span') }

      it 'creates an unfinished span' do
        expect(start_span.parent_span_id).to eq(otel_root_parent)
        expect(start_span.name).to eq('start-span')

        expect(spans).to be_empty
      end

      it 'records span on finish' do
        start_span.finish
        expect(span.name).to eq('start-span')
      end

      context 'with existing active span' do
        let!(:existing_span) { otel_tracer.start_span('existing-active-span') }

        include_context 'parent and child spans' do
          before do
            start_span.finish
            existing_span.finish
          end
        end

        it 'sets parent to active span' do
          expect(parent.name).to eq('existing-active-span')
          expect(child.name).to eq('start-span')
        end
      end
    end

    describe '#start_root_span' do
      subject(:start_root_span) { otel_tracer.start_root_span('start-root-span') }

      before { otel_tracer.start_span('existing-active-span') }

      it 'creates an unfinished span' do
        expect(start_root_span.parent_span_id).to eq(otel_root_parent)
        expect(start_root_span.name).to eq('start-root-span')

        expect(spans).to be_empty
      end

      it 'records span independently from other existing spans' do
        start_root_span.finish
        expect(span.name).to eq('start-root-span')
      end
    end

    context 'OpenTelemetry.logger' do
      it 'is the Datadog logger' do
        expect(::OpenTelemetry.logger).to eq(::Datadog.logger)
      end
    end

    context 'OpenTelemetry.propagation' do
      describe '#inject' do
        subject(:inject) { ::OpenTelemetry.propagation.inject(carrier) }
        let(:carrier) { {} }

        context 'with an active span' do
          before { otel_tracer.start_span('existing-active-span') }

          it 'injects Datadog headers' do
            inject
            expect(carrier).to eq(
              'x-datadog-parent-id' => Datadog::Tracing.active_span.id.to_s,
              'x-datadog-sampling-priority' => '1',
              'x-datadog-tags' => '_dd.p.dm=-0',
              'x-datadog-trace-id' => Datadog::Tracing.active_trace.id.to_s,
            )
          end
        end

        context 'with an active Datadog span' do
          before { tracer.trace('existing-active-span') }

          it 'injects Datadog headers' do
            inject
            expect(carrier).to eq(
              'x-datadog-parent-id' => Datadog::Tracing.active_span.id.to_s,
              'x-datadog-sampling-priority' => '1',
              'x-datadog-tags' => '_dd.p.dm=-0',
              'x-datadog-trace-id' => Datadog::Tracing.active_trace.id.to_s,
            )
          end
        end
      end

      describe '#extract' do
        subject(:extract) { ::OpenTelemetry.propagation.extract(carrier) }
        let(:carrier) { {} }

        context 'with Datadog headers' do
          let(:carrier) do
            {
              'x-datadog-parent-id' => '123',
              'x-datadog-sampling-priority' => '1',
              'x-datadog-tags' => '_dd.p.dm=-0',
              'x-datadog-trace-id' => '456',
            }
          end

          before do
            # Ensure background Writer worker doesn't wait, making tests faster.
            stub_const('Datadog::Tracing::Workers::AsyncTransport::DEFAULT_FLUSH_INTERVAL', 0)
          end

          it 'sucessive calls to #with_current leave tracer in a consistent state' do
            OpenTelemetry::Context.with_current(extract) do
              otel_tracer.in_span('otel') {}
            end

            OpenTelemetry::Context.with_current(extract) do
              otel_tracer.in_span('otel') {}
            end

            try_wait_until { spans[0]['_sampling_priority_v1'] } # Wait for TraceFormatter to modify the trace

            span = spans[0]

            expect(span.parent_id).to eq(123)
            expect(span.trace_id).to eq(456)
            expect(span['_dd.p.dm']).to eq('-0'), Datadog::Tracing.active_trace.inspect
            expect(span['_sampling_priority_v1']).to eq(1)

            span = spans[1]

            expect(span.parent_id).to eq(123)
            expect(span.trace_id).to eq(456)
            expect(span['_dd.p.dm']).to eq('-0'), Datadog::Tracing.active_trace.inspect
            expect(span['_sampling_priority_v1']).to eq(1)
          end

          it 'extracts into the active context' do
            OpenTelemetry::Context.with_current(extract) do
              otel_tracer.in_span('otel') {}
            end

            try_wait_until { span['_sampling_priority_v1'] } # Wait for TraceFormatter to modify the trace

            expect(span.parent_id).to eq(123)
            expect(span.trace_id).to eq(456)
            expect(span['_dd.p.dm']).to eq('-0') # , Datadog::Tracing.active_trace.inspect
            expect(span['_sampling_priority_v1']).to eq(1)
          end

          it 'extracts into the active Datadog context' do
            OpenTelemetry::Context.with_current(extract) do
              tracer.trace('datadog') {}
            end

            try_wait_until { span['_sampling_priority_v1'] } # Wait for TraceFormatter to modify the trace

            expect(span.parent_id).to eq(123)
            expect(span.trace_id).to eq(456)
            expect(span['_dd.p.dm']).to eq('-0'), Datadog::Tracing.active_trace.inspect
            expect(span['_sampling_priority_v1']).to eq(1)
          end
        end
      end
    end
  end
end
