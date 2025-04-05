require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/sidekiq/integration'
require 'datadog/tracing/contrib/sidekiq/client_tracer'
require 'datadog/tracing/contrib/sidekiq/server_tracer'

require 'sidekiq/testing'
require_relative 'support/helper'
require_relative 'support/legacy_test_helpers' if Sidekiq::VERSION < '4'
require 'sidekiq/api'

RSpec.describe 'Sidekiq distributed tracing' do
  include_context 'Sidekiq server'

  before do
    stub_const(
      'PropagationWorker',
      Class.new do
        include Sidekiq::Worker
        def perform
          # Save the trace digest in the job span for future inspection
          data = {}
          Datadog::Tracing::Contrib::Sidekiq.inject(Datadog::Tracing.active_trace.to_digest, data)
          Datadog::Tracing.active_span.set_tag('digest', data.to_json)
        end
      end
    )
  end

  context 'when distributed tracing enabled' do
    before do
      Datadog.configure do |c|
        c.tracing.instrument :sidekiq, distributed_tracing: true
      end
    end

    context 'when dispatching' do
      before do
        configure_sidekiq
        Sidekiq::Testing.fake!
        Sidekiq::Queues.clear_all
      end

      it 'propagates through serialized job' do
        EmptyWorker.perform_async

        job = EmptyWorker.jobs.first

        expect(span).to be_root_span
        expect(span.service).to eq(tracer.default_service)
        expect(span.resource).to eq('EmptyWorker')
        expect(span.get_tag('sidekiq.job.queue')).to eq('default')
        expect(span.status).to eq(0)
        expect(span.get_tag('component')).to eq('sidekiq')
        expect(span.get_tag('operation')).to eq('push')
        expect(span.get_tag('span.kind')).to eq('producer')

        expect(job['x-datadog-trace-id']).to eq(low_order_trace_id(span.trace_id).to_s)
        expect(job['x-datadog-parent-id']).to eq(span.id.to_s)
        expect(job['x-datadog-sampling-priority']).to eq('1')
        expect(job['x-datadog-tags']).to eq("_dd.p.dm=-0,_dd.p.tid=#{high_order_hex_trace_id(span.trace_id)}")
        expect(job).not_to include 'x-datadog-origin'
      end
    end

    context 'round trip' do
      it 'creates 2 spans for a distributed trace' do
        expect_in_sidekiq_server do
          Datadog::Tracing.trace('test setup') do |_span, trace|
            trace.sampling_priority = 2
            trace.origin = 'my-origin'
            trace.set_tag('_dd.p.dm', '-99')

            PropagationWorker.perform_async
          end

          job_span = fetch_job_span
          push_span = spans.find { |s| s.name == 'sidekiq.push' }

          expect(push_span.get_tag('sidekiq.job.id')).to eq(job_span.get_tag('sidekiq.job.id'))

          expect(job_span.trace_id).to eq(push_span.trace_id)
          expect(job_span.parent_id).to eq(push_span.id)

          digest = Datadog::Tracing::Contrib::Sidekiq.extract(JSON.parse(job_span.get_tag('digest')))

          expect(digest.trace_distributed_tags['_dd.p.dm']).to eq('-99')
          expect(digest.trace_sampling_priority).to eq(2)
          expect(digest.trace_origin).to eq('my-origin')
        end
      end
    end
  end

  context 'when distributed tracing disabled' do
    before do
      Datadog.configure do |c|
        c.tracing.instrument :sidekiq, distributed_tracing: false
      end
    end

    context 'when dispatching' do
      before do
        configure_sidekiq
        Sidekiq::Testing.fake!
        Sidekiq::Queues.clear_all
      end

      it 'does not propagate through serialized job' do
        EmptyWorker.perform_async

        job = EmptyWorker.jobs.first

        expect(span).to be_root_span
        expect(span.service).to eq(tracer.default_service)
        expect(span.resource).to eq('EmptyWorker')
        expect(span.get_tag('sidekiq.job.queue')).to eq('default')
        expect(span.status).to eq(0)
        expect(span.get_tag('component')).to eq('sidekiq')
        expect(span.get_tag('operation')).to eq('push')
        expect(span.get_tag('span.kind')).to eq('producer')

        expect(job).to_not include('x-datadog-trace-id')
        expect(job).to_not include('x-datadog-parent-id')
        expect(job).to_not include('x-datadog-sampling-priority')
        expect(job).to_not include('x-datadog-tags')
        expect(job).to_not include('x-datadog-origin')
      end
    end

    context 'round trip' do
      it 'creates 2 spans with separate traces' do
        expect_in_sidekiq_server do
          Datadog::Tracing.trace('test setup') do |_span, trace|
            trace.sampling_priority = 2
            trace.origin = 'my-origin'
            trace.set_tag('_dd.p.dm', '-99')

            PropagationWorker.perform_async
          end

          job_span = fetch_job_span
          push_span = spans.find { |s| s.name == 'sidekiq.push' }

          expect(push_span.trace_id).to_not eq(job_span.trace_id)
          expect(push_span.get_tag('sidekiq.job.id')).to eq(job_span.get_tag('sidekiq.job.id'))

          expect(job_span.resource).to eq('PropagationWorker')

          expect(job_span).to be_root_span
          expect(job_span.resource).to eq('PropagationWorker')

          digest = Datadog::Tracing::Contrib::Sidekiq.extract(JSON.parse(job_span.get_tag('digest')))

          expect(digest.trace_distributed_tags['_dd.p.dm']).to_not eq('-99')
          expect(digest.trace_sampling_priority).to_not eq(2)
          expect(digest.trace_origin).to_not eq('my-origin')
        end
      end
    end
  end
end
