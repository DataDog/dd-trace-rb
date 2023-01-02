# typed: ignore

require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/sidekiq/integration'
require 'datadog/tracing/contrib/sidekiq/client_tracer'
require 'datadog/tracing/contrib/sidekiq/server_tracer'

require 'sidekiq/testing'
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

  before do
    Datadog.configure do |c|
      c.tracing.instrument :sidekiq, distributed_tracing: true
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

  context 'when dispatching' do
    it do
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

      expect(job['x-datadog-trace-id']).to eq(span.trace_id.to_s)
      expect(job['x-datadog-parent-id']).to eq(span.id.to_s)
      expect(job['x-datadog-sampling-priority']).to eq('1')
      # expect(job["x-datadog-tags"]).to eq("_dd.p.dm=-0")
    end
  end

  context 'when receiving' do
    let(:trace_id) { Datadog::Tracing::Utils.next_id }
    let(:span_id) { Datadog::Tracing::Utils.next_id }
    let(:jid) { '123abc' }

    it do
      Sidekiq::Queues.push(
        EmptyWorker.queue,
        EmptyWorker.to_s,
        EmptyWorker.sidekiq_options.merge(
          'args' => [],
          'class' => EmptyWorker.to_s,
          'jid' => jid,
          'x-datadog-trace-id' => trace_id.to_s,
          'x-datadog-parent-id' => span_id.to_s,
          'x-datadog-sampling-priority' => '1',
          'x-datadog-tags' => '_dd.p.dm=-0',
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

      # "x-datadog-sampling-priority" => "1",
      # "x-datadog-tags" => "_dd.p.dm=-0",
    end
  end

  context 'round trip' do
    it do
      EmptyWorker.perform_async
      EmptyWorker.perform_one

      expect(spans).to have(2).items

      job_span, push_span = spans

      expect(push_span).to be_root_span

      expect(job_span.trace_id).to eq(push_span.trace_id)
      expect(job_span.parent_id).to eq(push_span.id)
    end
  end
end
