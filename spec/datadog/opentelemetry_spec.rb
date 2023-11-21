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
        c.tracing.distributed_tracing.propagation_style = ['Datadog'] # Ensure test has consistent propagation configuration
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
        subject!(:in_span) { otel_tracer.in_span('test', **options) {} }
        let(:options) { {} }

        it 'records a finished span' do
          expect(span).to be_root_span
          expect(span.name).to eq('test')
          expect(span.resource).to eq('test')
          expect(span.service).to eq(tracer.default_service)
        end

        context 'with attributes' do
          let(:options) { { attributes: attributes } }

          [
            [false, 'false'],
            ['str', 'str'],
            [[false], '[false]'],
            [['str'], '["str"]'],
            [[1], '[1]'],
          ].each do |input, expected|
            context "with attribute value #{input}" do
              let(:attributes) { { 'tag' => input } }

              it "sets tag #{expected}" do
                expect(span.get_tag('tag')).to eq(expected)
              end
            end
          end

          context 'with a numeric attribute' do
            let(:attributes) { { 'tag' => 1 } }

            it 'sets it as a metric' do
              expect(span.get_metric('tag')).to eq(1)
            end
          end

          context 'with reserved attributes' do
            let(:attributes) { { attribute_name => attribute_value } }

            context 'for operation.name' do
              let(:attribute_name) { 'operation.name' }
              let(:attribute_value) { 'Override.name' }

              it 'overrides the respective Datadog span name' do
                expect(span.name).to eq(attribute_value)
              end
            end

            context 'for resource.name' do
              let(:attribute_name) { 'resource.name' }
              let(:attribute_value) { 'new.name' }

              it 'overrides the respective Datadog span resource' do
                expect(span.resource).to eq(attribute_value)
              end
            end

            context 'for service.name' do
              let(:attribute_name) { 'service.name' }
              let(:attribute_value) { 'new.service.name' }

              it 'overrides the respective Datadog span service' do
                expect(span.service).to eq(attribute_value)
              end
            end

            context 'for span.type' do
              let(:attribute_name) { 'span.type' }
              let(:attribute_value) { 'new.span.type' }

              it 'overrides the respective Datadog span type' do
                expect(span.type).to eq(attribute_value)
              end
            end

            context 'for analytics.event' do
              let(:attribute_name) { 'analytics.event' }
              let(:attribute_value) { 'true' }

              it 'overrides the respective Datadog span tag' do
                expect(span.get_metric('_dd1.sr.eausr')).to eq(1)
              end
            end
          end
        end

        context 'with start_timestamp' do
          let(:options) { { start_timestamp: start_timestamp } }
          let(:start_timestamp) { Time.utc(2023) }
          it do
            expect(span.start_time).to eq(start_timestamp)
          end
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

          expect(spans).to have(2).items
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
      subject(:start_span) { otel_tracer.start_span('start-span', **options) }
      let(:options) { {} }

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

        context 'with parent and child spans' do
          include_context 'parent and child spans'

          before do
            start_span.finish
            existing_span.finish
          end

          it 'sets parent to active span' do
            expect(parent.name).to eq('existing-active-span')
            expect(child.name).to eq('start-span')
          end
        end

        context 'that has alrady finished' do
          let(:options) { { with_parent: ::OpenTelemetry::Trace.context_with_span(existing_span) } }
          let(:parent) { spans.find { |s| s.parent_id == 0 } }
          let(:child) { spans.find { |s| s != parent } }

          it 'correctly parents and flushed the child span' do
            existing_span.finish
            start_span.finish

            expect(parent).to be_root_span
            expect(child.parent_id).to eq(parent.id)
          end
        end
      end

      context 'and #finish with a timestamp' do
        let(:timestamp) { Time.utc(2023) }

        it 'sets the matching timestamp' do
          start_span.finish(end_timestamp: timestamp)

          expect(span.end_time).to eq(timestamp)
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

    shared_context 'Span#set_attribute' do
      subject(:set_attribute) { start_span.public_send(setter, attribute_name, attribute_value) }
      let(:start_span) { otel_tracer.start_span('start-span') }
      let(:active_span) { Datadog::Tracing.active_span }
      let(:attribute_name) { 'key' }
      let(:attribute_value) { 'value' }

      it 'sets Datadog tag' do
        start_span

        expect { set_attribute }.to change { active_span.get_tag('key') }.from(nil).to('value')

        start_span.finish

        expect(span.get_tag('key')).to eq('value')
      end

      context 'with reserved attributes' do
        before do
          set_attribute
          start_span.finish
        end

        context 'for operation.name' do
          let(:attribute_name) { 'operation.name' }
          let(:attribute_value) { 'Override.name' }

          it 'overrides the respective Datadog span name' do
            expect(span.name).to eq(attribute_value)
          end
        end

        context 'for resource.name' do
          let(:attribute_name) { 'resource.name' }
          let(:attribute_value) { 'new.name' }

          it 'overrides the respective Datadog span resource' do
            expect(span.resource).to eq(attribute_value)
          end
        end

        context 'for service.name' do
          let(:attribute_name) { 'service.name' }
          let(:attribute_value) { 'new.service.name' }

          it 'overrides the respective Datadog span service' do
            expect(span.service).to eq(attribute_value)
          end
        end

        context 'for span.type' do
          let(:attribute_name) { 'span.type' }
          let(:attribute_value) { 'new.span.type' }

          it 'overrides the respective Datadog span type' do
            expect(span.type).to eq(attribute_value)
          end
        end

        context 'for analytics.event' do
          let(:attribute_name) { 'analytics.event' }
          let(:attribute_value) { 'true' }

          it 'overrides the respective Datadog span tag' do
            expect(span.get_metric('_dd1.sr.eausr')).to eq(1)
          end
        end
      end
    end

    describe '#set_attribute' do
      include_context 'Span#set_attribute'
      let(:setter) { :set_attribute }
    end

    describe '#[]=' do
      include_context 'Span#set_attribute'
      let(:setter) { :[]= }
    end

    describe '#add_attributes' do
      subject(:add_attributes) { start_span.add_attributes({ 'k1' => 'v1', 'k2' => 'v2' }) }
      let(:start_span) { otel_tracer.start_span('start-span') }
      let(:active_span) { Datadog::Tracing.active_span }

      it 'sets Datadog tag' do
        start_span

        expect { add_attributes }.to change { active_span.get_tag('k1') }.from(nil).to('v1')

        start_span.finish

        expect(span.get_tag('k1')).to eq('v1')
        expect(span.get_tag('k2')).to eq('v2')
      end
    end

    describe '#status=' do
      subject! do
        start_span
        set_status
        start_span.finish
      end

      let(:set_status) { start_span.status = status }
      let(:start_span) { otel_tracer.start_span('start-span') }
      let(:active_span) { Datadog::Tracing.active_span }

      context 'with ok' do
        let(:status) { OpenTelemetry::Trace::Status.ok }

        it 'does not change status' do
          expect(span).to_not have_error
        end
      end

      context 'with error' do
        let(:status) { OpenTelemetry::Trace::Status.error('my-error') }

        it 'changes to error with a message' do
          expect(span).to have_error
          expect(span).to have_error_message('my-error')
          expect(span).to have_error_message(start_span.status.description)
        end

        context 'then ok' do
          subject! do
            start_span

            set_status # Sets to error
            start_span.status = OpenTelemetry::Trace::Status.ok

            start_span.finish
          end

          it 'cannot revert back from an error' do
            expect(span).to have_error
            expect(span).to have_error_message('my-error')
          end
        end

        context 'and another error' do
          subject! do
            start_span

            set_status # Sets to error
            start_span.status = OpenTelemetry::Trace::Status.error('another-error')

            start_span.finish
          end

          it 'overrides the error message' do
            expect(span).to have_error
            expect(span).to have_error_message('another-error')
            expect(span).to have_error_message(start_span.status.description)
          end
        end
      end

      context 'with unset' do
        let(:status) { OpenTelemetry::Trace::Status.unset }

        it 'does not change status' do
          expect(span).to_not have_error
        end
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
        def headers
          {
            'x-datadog-parent-id' => Datadog::Tracing.active_span.id.to_s,
            'x-datadog-sampling-priority' => '1',
            'x-datadog-tags' => '_dd.p.dm=-0,_dd.p.tid=' +
              high_order_hex_trace_id(Datadog::Tracing.active_trace.id),
            'x-datadog-trace-id' => low_order_trace_id(Datadog::Tracing.active_trace.id).to_s,
          }
        end

        context 'with an active span' do
          before { otel_tracer.start_span('existing-active-span') }

          it 'injects Datadog headers' do
            inject
            expect(carrier).to eq(headers)
          end
        end

        context 'with an active Datadog span' do
          before { tracer.trace('existing-active-span') }

          it 'injects Datadog headers' do
            inject
            expect(carrier).to eq(headers)
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

        context 'with TraceContext headers' do
          let(:carrier) do
            {
              'traceparent' => '00-00000000000000001111111111111111-2222222222222222-01'
            }
          end

          before do
            Datadog.configure do |c|
              c.tracing.distributed_tracing.propagation_extract_style = ['Datadog', 'tracecontext']
            end
          end

          it 'extracts into the active context' do
            OpenTelemetry::Context.with_current(extract) do
              otel_tracer.in_span('otel') {}
            end

            expect(span.trace_id).to eq(0x00000000000000001111111111111111)
            expect(span.parent_id).to eq(0x2222222222222222)
          end
        end
      end
    end
  end
end
