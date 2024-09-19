require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/sidekiq/integration'
require 'datadog/tracing/contrib/sidekiq/client_tracer'
require 'datadog/tracing/contrib/sidekiq/server_tracer'

require 'sidekiq/testing'
require_relative 'support/legacy_test_helpers' if Sidekiq::VERSION < '4'
require 'sidekiq/api'

RSpec.describe 'Sidekiq distributed tracing' do
  around do |example|
    Sidekiq::Testing.fake! do
      Sidekiq::Testing.server_middleware.clear
      Sidekiq::Testing.server_middleware do |chain|
        chain.add(Datadog::Tracing::Contrib::Sidekiq::ServerTracer)
      end

      example.run
    end
  end

  after do
    Datadog.configuration.tracing[:sidekiq].reset!
    Sidekiq::Queues.clear_all
  end

  let!(:empty_worker) do
    stub_const(
      'EmptyWorker',
      Class.new do
        include Sidekiq::Worker
        def perform; end
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

    context 'when receiving' do
      let(:trace_id) { Datadog::Tracing::Utils::TraceId.next_id }
      let(:span_id) { Datadog::Tracing::Utils.next_id }
      let(:jid) { '123abc' }

      it 'continues trace from serialized job' do
        Sidekiq::Queues.push(
          EmptyWorker.queue,
          EmptyWorker.to_s,
          EmptyWorker.sidekiq_options.merge(
            'args' => [],
            'class' => EmptyWorker.to_s,
            'jid' => jid,
            'x-datadog-trace-id' => low_order_trace_id(trace_id).to_s,
            'x-datadog-parent-id' => span_id.to_s,
            'x-datadog-sampling-priority' => '2',
            'x-datadog-tags' => "_dd.p.dm=-99,_dd.p.tid=#{high_order_hex_trace_id(trace_id)}",
            'x-datadog-origin' => 'my-origin'
          )
        )

        EmptyWorker.perform_one

        expect(span.trace_id).to eq(trace_id)
        expect(span.parent_id).to eq(span_id)
        expect(span.service).to eq(tracer.default_service)
        expect(span.resource).to eq('EmptyWorker')
        expect(span.get_tag('sidekiq.job.queue')).to eq('default')
        expect(span.status).to eq(0)
        expect(span.get_tag('component')).to eq('sidekiq')
        expect(span.get_tag('operation')).to eq('job')
        expect(span.get_tag('span.kind')).to eq('consumer')

        expect(trace.send(:meta)['_dd.p.dm']).to eq('-99')
        expect(trace.sampling_priority).to eq(2)
        expect(trace.origin).to eq('my-origin')
      end
    end

    context 'round trip' do
      it 'creates 2 spans for a distributed trace' do
        EmptyWorker.perform_async
        EmptyWorker.perform_one

        expect(spans).to have(2).items

        job_span, push_span = spans

        expect(push_span).to be_root_span
        expect(push_span.get_tag('sidekiq.job.id')).to eq(job_span.get_tag('sidekiq.job.id'))

        expect(job_span.trace_id).to eq(push_span.trace_id)
        expect(job_span.parent_id).to eq(push_span.id)
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

    context 'when receiving' do
      let(:trace_id) { Datadog::Tracing::Utils::TraceId.next_id }
      let(:span_id) { Datadog::Tracing::Utils.next_id }
      let(:jid) { '123abc' }

      it 'does not continue trace from serialized job' do
        Sidekiq::Queues.push(
          EmptyWorker.queue,
          EmptyWorker.to_s,
          EmptyWorker.sidekiq_options.merge(
            'args' => [],
            'class' => EmptyWorker.to_s,
            'jid' => jid,
            'x-datadog-trace-id' => trace_id.to_s,
            'x-datadog-parent-id' => span_id.to_s,
            'x-datadog-sampling-priority' => '2',
            'x-datadog-tags' => '_dd.p.dm=99',
            'x-datadog-origin' => 'my-origin'
          )
        )

        EmptyWorker.perform_one

        expect(span).to be_root_span
        expect(span.trace_id).not_to eq(trace_id)
        expect(span.parent_id).to eq(0)
        expect(span.service).to eq(tracer.default_service)
        expect(span.resource).to eq('EmptyWorker')
        expect(span.get_tag('sidekiq.job.queue')).to eq('default')
        expect(span.status).to eq(0)
        expect(span.get_tag('component')).to eq('sidekiq')
        expect(span.get_tag('operation')).to eq('job')
        expect(span.get_tag('span.kind')).to eq('consumer')

        expect(trace.send(:meta)['_dd.p.dm']).to eq('-0')
        expect(trace.sampling_priority).to eq(1)
        expect(trace.origin).to be_nil
      end
    end

    context 'round trip' do
      it 'creates 2 spans with separate traces' do
        EmptyWorker.perform_async
        EmptyWorker.perform_one

        expect(spans).to have(2).items

        job_span, push_span = spans

        expect(push_span.trace_id).to_not eq(job_span.trace_id)
        expect(push_span.get_tag('sidekiq.job.id')).to eq(job_span.get_tag('sidekiq.job.id'))

        expect(push_span).to be_root_span
        expect(job_span.resource).to eq('EmptyWorker')

        expect(job_span).to be_root_span
        expect(job_span.resource).to eq('EmptyWorker')
      end
    end
  end
end
