# typed: ignore
require 'spec_helper'
require 'ddtrace/trace_operation'

require 'ddtrace/transport/serializable_trace'

RSpec.describe Datadog::TraceOperation do
  subject(:trace_op) { described_class.new(**options) }
  let(:options) { {} }

  context 'for a mock job with fan-out/fan-in behavior' do
    subject(:trace) do
      @thread_traces = Queue.new

      trace_op.measure('job', resource: 'import_job', service: 'job-worker') do |_span, trace|
        trace.measure('load_data', resource: 'imports.csv') do
          trace.measure('read_file', resource: 'imports.csv') do
            sleep(0.01)
          end

          trace.measure('deserialize', resource: 'inventory') do
            sleep(0.01)
          end
        end

        workers = nil
        trace.measure('start_inserts', resource: 'inventory') do
          trace_digest = trace.to_digest

          workers = Array.new(5) do |index|
            Thread.new do
              # Delay start-up slightly
              sleep(0.01)

              thread_trace = described_class.new(
                id: trace_digest.trace_id,
                origin: trace_digest.trace_origin,
                parent_span_id: trace_digest.span_id,
                sampling_priority: trace_digest.trace_sampling_priority
              )

              @thread_traces.push(thread_trace)

              thread_trace.measure(
                'db.query',
                service: 'database',
                resource: "worker #{index}"
              ) do
                sleep(0.01)
              end
            end
          end
        end

        trace.measure('wait_inserts', resource: 'inventory') do |wait_span|
          wait_span.set_tag('worker.count', workers.length)
          workers && workers.each { |w| w.alive? && w.join }
        end

        trace.measure('update_log', resource: 'inventory') do
          sleep(0.01)
        end
      end

      trace_op.flush!
    end

    it 'is a well-formed trace' do
      expect { trace }.to_not raise_error

      # Collect traces from threads
      all_thread_traces = []
      all_thread_traces << @thread_traces.pop until @thread_traces.empty?

      # Collect spans from original trace + threads
      all_spans = (trace.spans + all_thread_traces.collect { |t| t.flush!.spans }).flatten
      expect(all_spans).to have(12).items

      job_span = all_spans.find { |s| s.name == 'job' }
      load_data_span = all_spans.find { |s| s.name == 'load_data' }
      read_file_span = all_spans.find { |s| s.name == 'read_file' }
      deserialize_span = all_spans.find { |s| s.name == 'deserialize' }
      start_inserts_span = all_spans.find { |s| s.name == 'start_inserts' }
      db_query_spans = all_spans.select { |s| s.name == 'db.query' }
      wait_insert_span = all_spans.find { |s| s.name == 'wait_inserts' }
      update_log_span = all_spans.find { |s| s.name == 'update_log' }

      trace_id = job_span.trace_id

      expect(job_span).to have_attributes(
        trace_id: (a_value > 0),
        id: (a_value > 0),
        parent_id: 0,
        name: 'job',
        resource: 'import_job',
        service: 'job-worker'
      )

      expect(load_data_span).to have_attributes(
        trace_id: trace_id,
        id: (a_value > 0),
        parent_id: job_span.id,
        name: 'load_data',
        resource: 'imports.csv',
        service: 'job-worker'
      )

      expect(read_file_span).to have_attributes(
        trace_id: trace_id,
        id: (a_value > 0),
        parent_id: load_data_span.id,
        name: 'read_file',
        resource: 'imports.csv',
        service: 'job-worker'
      )

      expect(deserialize_span).to have_attributes(
        trace_id: trace_id,
        id: (a_value > 0),
        parent_id: load_data_span.id,
        name: 'deserialize',
        resource: 'inventory',
        service: 'job-worker'
      )

      expect(start_inserts_span).to have_attributes(
        trace_id: trace_id,
        id: (a_value > 0),
        parent_id: job_span.id,
        name: 'start_inserts',
        resource: 'inventory',
        service: 'job-worker'
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
        service: 'job-worker'
      )
      expect(wait_insert_span.get_tag('worker.count')).to eq(5.0)

      expect(update_log_span).to have_attributes(
        trace_id: trace_id,
        id: (a_value > 0),
        parent_id: job_span.id,
        name: 'update_log',
        resource: 'inventory',
        service: 'job-worker'
      )
    end
  end
end
