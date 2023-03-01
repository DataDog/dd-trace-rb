require 'spec_helper'

require 'datadog/core/runtime/ext'

require 'datadog/tracing/propagation/http'
require 'datadog/tracing/sampling/ext'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/tracer'
require 'datadog/tracing/utils'

RSpec.describe Datadog::Tracing::Tracer do
  subject(:tracer) { described_class.new(writer: FauxWriter.new) }

  let(:spans) { tracer.writer.spans(:keep) }

  after do
    tracer.shutdown! # Ensure no state gets left behind
  end

  def lang_tag(span)
    span.get_tag(Datadog::Core::Runtime::Ext::TAG_LANG)
  end

  describe 'manual tracing' do
    context 'for simple nested spans' do
      subject(:traces) do
        grandparent = tracer.trace('grandparent')
        parent = tracer.trace('parent')
        child = tracer.trace('child')
        child.finish
        parent.finish
        grandparent.finish

        writer.traces
      end

      it 'is a well-formed trace' do
        expect(traces).to have(1).item
        trace = traces.first
        all_spans = trace.spans

        grandparent_span = all_spans.find { |s| s.name == 'grandparent' }
        parent_span = all_spans.find { |s| s.name == 'parent' }
        child_span = all_spans.find { |s| s.name == 'child' }

        trace_id = grandparent_span.trace_id

        expect(grandparent_span).to have_attributes(
          trace_id: (a_value > 0),
          id: (a_value > 0),
          parent_id: 0,
          name: 'grandparent'
        )

        expect(parent_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: grandparent_span.id,
          name: 'parent'
        )

        expect(child_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: parent_span.id,
          name: 'child'
        )
      end
    end

    context 'for a mock job with fan-out/fan-in behavior' do
      subject(:job) do
        tracer.trace('job', resource: 'import_job') do |_span, trace|
          tracer.trace('load_data', resource: 'imports.csv') do
            tracer.trace('read_file', resource: 'imports.csv') do
              sleep(0.01)
            end

            tracer.trace('deserialize', resource: 'inventory') do
              sleep(0.01)
            end
          end

          workers = nil
          tracer.trace('start_inserts', resource: 'inventory') do
            trace_digest = trace.to_digest

            workers = Array.new(5) do |index|
              Thread.new do
                # Delay start-up slightly
                sleep(0.01)

                tracer.trace(
                  'db.query',
                  service: 'database',
                  resource: "worker #{index}",
                  continue_from: trace_digest
                ) do
                  sleep(0.01)
                end
              end
            end
          end

          tracer.trace('wait_inserts', resource: 'inventory') do |wait_span|
            wait_span.set_tag('worker.count', workers.length)
            workers && workers.each(&:join)
          end

          tracer.trace('update_log', resource: 'inventory') do
            sleep(0.01)
          end
        end
      end

      it 'is a well-formed trace' do
        expect { job }.to_not raise_error

        # Collect spans from original trace + threads
        expect(spans).to have(12).items

        job_span = spans.find { |s| s.name == 'job' }
        load_data_span = spans.find { |s| s.name == 'load_data' }
        read_file_span = spans.find { |s| s.name == 'read_file' }
        deserialize_span = spans.find { |s| s.name == 'deserialize' }
        start_inserts_span = spans.find { |s| s.name == 'start_inserts' }
        db_query_spans = spans.select { |s| s.name == 'db.query' }
        wait_insert_span = spans.find { |s| s.name == 'wait_inserts' }
        update_log_span = spans.find { |s| s.name == 'update_log' }

        trace_id = job_span.trace_id

        expect(job_span).to have_attributes(
          trace_id: (a_value > 0),
          id: (a_value > 0),
          parent_id: 0,
          name: 'job',
          resource: 'import_job',
          service: tracer.default_service
        )

        expect(load_data_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: job_span.id,
          name: 'load_data',
          resource: 'imports.csv',
          service: tracer.default_service
        )

        expect(read_file_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: load_data_span.id,
          name: 'read_file',
          resource: 'imports.csv',
          service: tracer.default_service
        )

        expect(deserialize_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: load_data_span.id,
          name: 'deserialize',
          resource: 'inventory',
          service: tracer.default_service
        )

        expect(start_inserts_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: job_span.id,
          name: 'start_inserts',
          resource: 'inventory',
          service: tracer.default_service
        )

        expect(db_query_spans).to all(
          have_attributes(
            trace_id: trace_id,
            id: (a_value > 0),
            parent_id: start_inserts_span.id,
            name: 'db.query',
            resource: /worker \d+/,
            service: 'database'
          )
        )

        expect(wait_insert_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: job_span.id,
          name: 'wait_inserts',
          resource: 'inventory',
          service: tracer.default_service
        )
        expect(wait_insert_span.get_tag('worker.count')).to eq(5.0)

        expect(update_log_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: job_span.id,
          name: 'update_log',
          resource: 'inventory',
          service: tracer.default_service
        )
      end
    end

    context 'that continues from another trace' do
      context 'without a block' do
        before do
          tracer.continue_trace!(digest)
          tracer.trace('my.job').finish
        end

        context 'with state' do
          let(:digest) do
            Datadog::Tracing::TraceDigest.new(
              span_id: Datadog::Tracing::Utils.next_id,
              trace_id: Datadog::Tracing::Utils.next_id,
              trace_origin: 'synthetics',
              trace_sampling_priority: Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
            )
          end

          it 'clears the active trace after finishing' do
            expect(spans).to have(1).item
            expect(span.name).to eq('my.job')
            expect(tracer.active_trace).to be nil
          end
        end

        context 'without state' do
          let(:digest) { nil }

          it 'clears the active trace after finishing' do
            expect(spans).to have(1).item
            expect(span.name).to eq('my.job')
            expect(tracer.active_trace).to be nil
          end
        end
      end
    end
  end

  describe 'synthetics' do
    context 'which applies the context from distributed tracing headers' do
      let(:trace_id) { 3238677264721744442 }
      let(:synthetics_trace) { Datadog::Tracing::Propagation::HTTP.extract(distributed_tracing_headers) }
      let(:parent_id) { 0 }
      let(:sampling_priority) { 1 }
      let(:origin) { 'synthetics' }

      let(:distributed_tracing_headers) do
        {
          RackSupport.header_to_rack('x-datadog-trace-id') => trace_id.to_s,
          RackSupport.header_to_rack('x-datadog-parent-id') => parent_id.to_s,
          RackSupport.header_to_rack('x-datadog-sampling-priority') => sampling_priority.to_s,
          RackSupport.header_to_rack('x-datadog-origin') => origin
        }
      end

      before do
        tracer.continue_trace!(synthetics_trace)
      end

      shared_examples_for 'a synthetics-sourced trace' do
        before do
          tracer.trace('local.operation') do |local_span_op|
            @local_span = local_span_op
          end
        end

        let(:local_trace) { traces.first }
        let(:local_span) { local_trace.spans.first }

        it 'that is well-formed' do
          expect(local_trace).to_not be nil
          expect(local_trace.origin).to eq(origin)
          expect(local_trace.sampling_priority).to eq(sampling_priority)

          expect(local_span.id).to eq(@local_span.id)
          expect(local_span.trace_id).to eq(trace_id)
          expect(local_span.parent_id).to eq(parent_id)
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

  describe 'distributed trace' do
    let(:extract) { Datadog::Tracing::Propagation::HTTP.extract(rack_headers) }
    let(:trace) { Datadog::Tracing.continue_trace!(extract) }
    let(:inject) { {}.tap { |env| Datadog::Tracing::Propagation::HTTP.inject!(trace.to_digest, env) } }

    let(:rack_headers) { headers.map { |k, v| [RackSupport.header_to_rack(k), v] }.to_h }

    after { Datadog::Tracing.continue_trace!(nil) }

    context 'with distributed datadog headers' do
      let(:headers) do
        {
          'x-datadog-trace-id' => trace_id.to_s,
          'x-datadog-parent-id' => parent_id.to_s,
          'x-datadog-origin' => origin,
          'x-datadog-sampling-priority' => sampling_priority.to_s,
          'x-datadog-tags' => distributed_tags,
        }
      end

      let(:trace_id) { 123 }
      let(:parent_id) { 456 }
      let(:origin) { 'outer-space' }
      let(:sampling_priority) { 1 }
      let(:distributed_tags) { '_dd.p.test=value' }

      it 'populates active trace' do
        expect(trace.id).to eq(trace_id)
        expect(trace.parent_span_id).to eq(parent_id)
        expect(trace.origin).to eq(origin)
        expect(trace.sampling_priority).to eq(sampling_priority)
        expect(trace.send(:distributed_tags)).to eq('_dd.p.test' => 'value')
      end

      it 'populates injected request headers' do
        expect(inject).to include(headers)
      end

      it 'populates injected request headers when values are modified' do
        trace.origin = 'other-origin'
        trace.sampling_priority = 9
        trace.set_tag('_dd.p.test', 'changed')

        expect(inject).to include(
          'x-datadog-origin' => 'other-origin',
          'x-datadog-sampling-priority' => '9',
          'x-datadog-tags' => '_dd.p.test=changed',
        )
      end
    end

    context 'with distributed Trace Context headers' do
      before do
        Datadog.configure do |c|
          c.tracing.distributed_tracing.propagation_extract_style = ['tracecontext']
          c.tracing.distributed_tracing.propagation_inject_style = ['tracecontext']
        end
      end

      let(:headers) do
        {
          'traceparent' => '00-0000000000000000000000000000007b-00000000000001c8-01',
          'tracestate' => 'dd=s:1;o:orig;t.test:value',
        }
      end

      it 'populates active trace' do
        expect(trace.id).to eq(0x7b)
        expect(trace.parent_span_id).to eq(0x1c8)
        expect(trace.origin).to eq('orig')
        expect(trace.sampling_priority).to eq(1)
        expect(trace.send(:distributed_tags)).to eq('_dd.p.test' => 'value')
      end

      it 'populates injected request headers' do
        expect(inject).to include(headers)
      end

      it 'populates injected request headers when values are modified' do
        trace.origin = 'other-origin'
        trace.sampling_priority = 9
        trace.set_tag('_dd.p.test', 'changed')

        expect(inject).to eq(
          'traceparent' => '00-0000000000000000000000000000007b-00000000000001c8-01',
          'tracestate' => 'dd=s:9;o:other-origin;t.test:changed'
        )
      end
    end
  end
end
