# typed: false
require 'spec_helper'

require 'datadog/core/runtime/ext'
require 'datadog/core/utils'
require 'datadog/tracing/propagation/http'
require 'datadog/tracing/sampling/ext'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/tracer'

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
              span_id: Datadog::Core::Utils.next_id,
              trace_id: Datadog::Core::Utils.next_id,
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
          rack_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID) => trace_id.to_s,
          rack_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID) => parent_id.to_s,
          rack_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_SAMPLING_PRIORITY) => sampling_priority.to_s,
          rack_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_ORIGIN) => origin
        }
      end

      def rack_header(header)
        "http-#{header}".upcase!.tr('-', '_')
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
end
