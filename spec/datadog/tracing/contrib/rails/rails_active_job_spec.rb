# This module tests the right integration between Sidekiq and
# Rails. Functionality tests for Rails and Sidekiq must go
# in their testing modules.
begin
  require 'sidekiq/testing'
  require 'datadog/tracing/contrib/sidekiq/server_tracer'
rescue LoadError
  puts 'Sidekiq testing harness not loaded'
end

begin
  require 'active_job'
rescue LoadError
  puts 'ActiveJob not supported in this version of Rails'
end

require 'datadog/tracing/contrib/rails/rails_helper'
require 'datadog/tracing/contrib/active_job/integration'

RSpec.describe 'ActiveJob' do
  before { skip unless defined? ::ActiveJob }
  after { remove_patch!(:active_job) }
  include_context 'Rails test application'

  context 'with active_job instrumentation' do
    subject(:job_class) do
      stub_const('JOB_EXECUTIONS',  Concurrent::AtomicFixnum.new(0))
      stub_const('JobDiscardError', Class.new(StandardError))
      stub_const('JobRetryError', Class.new(StandardError))

      stub_const(
        'ExampleJob',
        Class.new(ActiveJob::Base) do
          def perform(test_retry: false, test_discard: false)
            ActiveJob::Base.logger.info 'MINASWAN'
            JOB_EXECUTIONS.increment
            raise JobRetryError if test_retry
            raise JobDiscardError if test_discard
          end
        end
      )
      ExampleJob.discard_on(JobDiscardError) if ExampleJob.respond_to?(:discard_on)
      ExampleJob.retry_on(JobRetryError, attempts: 2, wait: 2) { nil } if ExampleJob.respond_to?(:retry_on)

      ExampleJob
    end

    before do
      Datadog.configure do |c|
        c.tracing.instrument :active_job
      end

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('USE_TAGGED_LOGGING').and_return(true)

      # initialize the application
      app

      # Override inline adapter to execute scheduled jobs for testingrails_active_job_spec
      if ActiveJob::QueueAdapters::InlineAdapter.respond_to?(:enqueue_at)
        allow(ActiveJob::QueueAdapters::InlineAdapter)
          .to receive(:enqueue_at) do |job, _timestamp, *job_args|
            ActiveJob::QueueAdapters::InlineAdapter.enqueue(job, *job_args)
          end
      else
        allow_any_instance_of(ActiveJob::QueueAdapters::InlineAdapter)
          .to receive(:enqueue_at) do |adapter, job, _timestamp|
            adapter.enqueue(job)
          end
      end
    end

    it 'instruments enqueue' do
      job_class.set(queue: :mice, priority: -10).perform_later

      span = spans.find { |s| s.name == 'active_job.enqueue' }
      expect(span.name).to eq('active_job.enqueue')
      expect(span.resource).to eq('ExampleJob')
      expect(span.get_tag('active_job.adapter')).to eq('ActiveJob::QueueAdapters::InlineAdapter')
      expect(span.get_tag('active_job.job.id')).to match(/[0-9a-f\-]{32}/)
      expect(span.get_tag('active_job.job.queue')).to eq('mice')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_job')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('enqueue')

      if Datadog::Tracing::Contrib::ActiveJob::Integration.version >= Gem::Version.new('5.0')
        expect(span.get_tag('active_job.job.priority')).to eq(-10)
      end
    end

    it 'instruments enqueue_at under the "enqueue" span' do
      scheduled_at = 1.minute.from_now
      job_class.set(queue: :mice, priority: -10, wait_until: scheduled_at).perform_later

      span = spans.find { |s| s.name == 'active_job.enqueue' }
      expect(span.name).to eq('active_job.enqueue')
      expect(span.resource).to eq('ExampleJob')
      expect(span.get_tag('active_job.adapter')).to eq('ActiveJob::QueueAdapters::InlineAdapter')
      expect(span.get_tag('active_job.job.id')).to match(/[0-9a-f\-]{32}/)
      expect(span.get_tag('active_job.job.queue')).to eq('mice')
      expect(span.get_tag('active_job.job.scheduled_at').to_time).to be_within(1).of(scheduled_at)
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_job')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('enqueue_at')

      if Datadog::Tracing::Contrib::ActiveJob::Integration.version >= Gem::Version.new('5.0')
        expect(span.get_tag('active_job.job.priority')).to eq(-10)
      end
    end

    it 'instruments perform' do
      job_class.set(queue: :elephants, priority: -10).perform_later

      span = spans.find { |s| s.name == 'active_job.perform' }
      expect(span.name).to eq('active_job.perform')
      expect(span.resource).to eq('ExampleJob')
      expect(span.get_tag('active_job.adapter')).to eq('ActiveJob::QueueAdapters::InlineAdapter')
      expect(span.get_tag('active_job.job.id')).to match(/[0-9a-f\-]{32}/)
      expect(span.get_tag('active_job.job.queue')).to eq('elephants')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_job')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('perform')

      if Datadog::Tracing::Contrib::ActiveJob::Integration.version >= Gem::Version.new('5.0')
        expect(span.get_tag('active_job.job.priority')).to eq(-10)
      end
    end

    it 'instruments active_job.enqueue_retry and active_job.retry_stopped' do
      unless Datadog::Tracing::Contrib::ActiveJob::Integration.version >= Gem::Version.new('6.0')
        skip('ActiveSupport instrumentation for Retry introduced in Rails 6')
      end

      job_class.set(queue: :elephants, priority: -10).perform_later(test_retry: true)

      enqueue_retry_span = spans.find { |s| s.name == 'active_job.enqueue_retry' }
      expect(enqueue_retry_span.name).to eq('active_job.enqueue_retry')
      expect(enqueue_retry_span.resource).to eq('ExampleJob')
      expect(enqueue_retry_span.get_tag('active_job.adapter')).to eq('ActiveJob::QueueAdapters::InlineAdapter')
      expect(enqueue_retry_span.get_tag('active_job.job.id')).to match(/[0-9a-f\-]{32}/)
      expect(enqueue_retry_span.get_tag('active_job.job.queue')).to eq('elephants')
      expect(enqueue_retry_span.get_tag('active_job.job.error')).to eq('JobRetryError')
      expect(enqueue_retry_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_job')
      expect(enqueue_retry_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('enqueue_retry')

      # Rails 6 introduced "jitter" so the wait will not be exactly the set(wait: 2) value
      expect(enqueue_retry_span.get_tag('active_job.job.retry_wait')).to be_within(1).of(2)

      if Datadog::Tracing::Contrib::ActiveJob::Integration.version >= Gem::Version.new('5.0')
        expect(enqueue_retry_span.get_tag('active_job.job.priority')).to eq(-10)
      end

      retry_stopped_span = spans.find { |s| s.name == 'active_job.retry_stopped' }
      expect(retry_stopped_span.name).to eq('active_job.retry_stopped')
      expect(retry_stopped_span.resource).to eq('ExampleJob')
      expect(retry_stopped_span.get_tag('active_job.adapter')).to eq('ActiveJob::QueueAdapters::InlineAdapter')
      expect(retry_stopped_span.get_tag('active_job.job.id')).to match(/[0-9a-f\-]{32}/)
      expect(retry_stopped_span.get_tag('active_job.job.queue')).to eq('elephants')
      expect(retry_stopped_span.get_tag('active_job.job.error')).to eq('JobRetryError')
      expect(retry_stopped_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_job')
      expect(retry_stopped_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('retry_stopped')

      if Datadog::Tracing::Contrib::ActiveJob::Integration.version >= Gem::Version.new('5.0')
        expect(retry_stopped_span.get_tag('active_job.job.priority')).to eq(-10)
      end
    end

    it 'instruments discard' do
      unless Datadog::Tracing::Contrib::ActiveJob::Integration.version >= Gem::Version.new('6.0')
        skip('ActiveSupport instrumentation for Discard introduced in Rails 6')
      end

      job_class.set(queue: :elephants, priority: -10).perform_later(test_discard: true)

      span = spans.find { |s| s.name == 'active_job.discard' }
      expect(span.name).to eq('active_job.discard')
      expect(span.resource).to eq('ExampleJob')
      expect(span.get_tag('active_job.adapter')).to eq('ActiveJob::QueueAdapters::InlineAdapter')
      expect(span.get_tag('active_job.job.id')).to match(/[0-9a-f\-]{32}/)
      expect(span.get_tag('active_job.job.queue')).to eq('elephants')
      expect(span.get_tag('active_job.job.error')).to eq('JobDiscardError')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_job')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('discard')

      if Datadog::Tracing::Contrib::ActiveJob::Integration.version >= Gem::Version.new('5.0')
        expect(span.get_tag('active_job.job.priority')).to eq(-10)
      end
    end

    it 'injects active correlation into logs' do
      job_class.set(queue: :elephants, priority: -10).perform_later

      logs = log_output.string
      span = spans.find { |s| s.name == 'active_job.perform' }

      expect(logs).to include(span.trace_id.to_s)
      expect(logs).to include('MINASWAN')
    end
  end

  context 'with Sidekiq instrumentation' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('USE_SIDEKIQ').and_return('true')
    end

    before do
      Sidekiq.configure_client do |config|
        config.redis = { url: ENV['REDIS_URL'] }
      end

      Sidekiq.configure_server do |config|
        config.redis = { url: ENV['REDIS_URL'] }
      end

      Sidekiq::Testing.inline!
    end

    before { app }

    context 'with a Sidekiq::Worker' do
      subject(:worker) do
        stub_const(
          'EmptyWorker',
          Class.new do
            include Sidekiq::Worker

            def perform; end
          end
        )
      end

      it 'has correct Sidekiq span' do
        worker.perform_async

        expect(span.name).to eq('sidekiq.job')
        expect(span.resource).to eq('EmptyWorker')
        expect(span.get_tag('sidekiq.job.wrapper')).to be_nil
        expect(span.get_tag('sidekiq.job.id')).to match(/[0-9a-f]{24}/)
        expect(span.get_tag('sidekiq.job.retry')).to eq('true')
        expect(span.get_tag('sidekiq.job.queue')).to eq('default')
        expect(span.get_tag('span.kind')).to eq('consumer')
        expect(span.get_tag('messaging.system')).to eq('sidekiq')
      end
    end

    context 'with an ActiveJob' do
      subject(:worker) do
        stub_const(
          'EmptyJob',
          Class.new(ActiveJob::Base) do
            def perform; end
          end
        )
      end

      it 'has correct Sidekiq span' do
        worker.perform_later

        # depending on test order, the active_job integration may already have been enabled
        # which means there may be multiple spans. Find the sidekiq one:
        span = spans.find { |s| s.name == 'sidekiq.job' }

        expect(span.name).to eq('sidekiq.job')
        expect(span.resource).to eq('EmptyJob')
        expect(span.get_tag('sidekiq.job.wrapper')).to eq('ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper')
        expect(span.get_tag('sidekiq.job.id')).to match(/[0-9a-f]{24}/)
        expect(span.get_tag('sidekiq.job.retry')).to eq('true')
        expect(span.get_tag('sidekiq.job.queue')).to eq('default')
        expect(span.get_tag('span.kind')).to eq('consumer')
        expect(span.get_tag('messaging.system')).to eq('sidekiq')
      end

      context 'when active_job tracing is also enabled' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :active_job
          end
        end

        it 'records both active_job and sidekiq' do
          worker.perform_later

          sidekiq_span = spans.find { |s| s.name == 'sidekiq.job' }
          active_job_span = spans.find { |s| s.name == 'active_job.perform' }

          expect(sidekiq_span).to be_present
          expect(active_job_span).to be_present
        end
      end
    end
  end
end
