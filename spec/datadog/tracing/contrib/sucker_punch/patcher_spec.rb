require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'sucker_punch'
require 'ddtrace'

RSpec.describe 'sucker_punch instrumentation' do
  before do
    Datadog.configure do |c|
      c.tracing.instrument :sucker_punch
    end

    SuckerPunch::RUNNING.make_true
  end

  after do
    count = Thread.list.size

    SuckerPunch::RUNNING.make_false
    SuckerPunch::Queue.all.each(&:shutdown)
    SuckerPunch::Queue.clear

    next unless expect_thread?

    # Unfortunately, SuckerPunch queues (which are concurrent-ruby
    # ThreadPoolExecutor instances) don't have an interface that
    # waits until threads have completely terminated.
    # Even methods like
    # http://ruby-concurrency.github.io/concurrent-ruby/1.1.8/Concurrent/ThreadPoolExecutor.html#wait_for_termination-instance_method
    # only wait until the executor is guaranteed to not process any
    # more items, but not necessarily decommission all resources.
    try_wait_until { Thread.list.size < count }
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:sucker_punch].reset_configuration!
    example.run
    Datadog.registry[:sucker_punch].reset_configuration!
  end

  let(:expect_thread?) { true }

  let(:worker_class) do
    Class.new do
      include SuckerPunch::Job

      def perform(action = :none, **_)
        1 / 0 if action == :fail
      end
    end
  end

  context 'successful job' do
    subject(:dummy_worker_success) { worker_class.perform_async }

    let(:job_span) { spans.find { |s| s.resource[/PROCESS/] } }
    let(:enqueue_span) { spans.find { |s| s.resource[/ENQUEUE/] } }
    let(:span) { spans.first }

    it_behaves_like 'measured span for integration', true do
      before do
        dummy_worker_success
        try_wait_until { fetch_spans.length == 2 }
      end
    end

    it 'generates two spans, one for pushing to enqueue and one for the job itself' do
      is_expected.to be true
      try_wait_until { fetch_spans.length == 2 }
      expect(spans.length).to eq(2)
    end

    it 'instruments successful job' do
      is_expected.to be true
      try_wait_until { fetch_spans.length == 2 }

      expect(job_span.service).to eq(tracer.default_service)
      expect(job_span.name).to eq('sucker_punch.perform')
      expect(job_span.resource).to eq("PROCESS #{worker_class}")
      expect(job_span.get_tag('sucker_punch.queue')).to eq(worker_class.to_s)
      expect(job_span.status).not_to eq(Datadog::Tracing::Metadata::Ext::Errors::STATUS)
      expect(job_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sucker_punch')
      expect(job_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('perform')
    end

    it 'instruments successful enqueuing' do
      is_expected.to be true
      try_wait_until { fetch_spans.length == 2 }

      expect(enqueue_span.service).to eq(tracer.default_service)
      expect(enqueue_span.name).to eq('sucker_punch.perform_async')
      expect(enqueue_span.resource).to eq("ENQUEUE #{worker_class}")
      expect(enqueue_span.get_tag('sucker_punch.queue')).to eq(worker_class.to_s)
      expect(enqueue_span.get_metric('_dd.measured')).to eq(1.0)
      expect(enqueue_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sucker_punch')
      expect(enqueue_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('perform_async')
    end
  end

  context 'failed job' do
    subject(:dummy_worker_fail) { worker_class.perform_async(:fail) }

    let(:job_span) { spans.find { |s| s.resource[/PROCESS/] } }
    let(:span) { spans.first }

    it_behaves_like 'measured span for integration', true do
      before do
        dummy_worker_fail
        try_wait_until { fetch_spans.length == 2 }
      end
    end

    it 'instruments a failed job' do
      is_expected.to be true
      try_wait_until { fetch_spans.length == 2 }

      expect(job_span.service).to eq(tracer.default_service)
      expect(job_span.name).to eq('sucker_punch.perform')
      expect(job_span.resource).to eq("PROCESS #{worker_class}")
      expect(job_span.get_tag('sucker_punch.queue')).to eq(worker_class.to_s)
      expect(job_span).to have_error
      expect(job_span).to have_error_type('ZeroDivisionError')
      expect(job_span).to have_error_message('divided by 0')
    end
  end

  context 'delayed job' do
    subject(:dummy_worker_delay) { worker_class.perform_in(0) }

    let(:enqueue_span) { spans.find { |s| s.resource[/ENQUEUE/] } }
    let(:span) { spans.first }

    it_behaves_like 'measured span for integration', true do
      before do
        dummy_worker_delay
        try_wait_until { fetch_spans.length == 2 }
      end
    end

    it 'instruments enqueuing for a delayed job' do
      dummy_worker_delay
      try_wait_until { fetch_spans.length == 2 }

      expect(enqueue_span.service).to eq(tracer.default_service)
      expect(enqueue_span.name).to eq('sucker_punch.perform_in')
      expect(enqueue_span.resource).to eq("ENQUEUE #{worker_class}")
      expect(enqueue_span.get_tag('sucker_punch.queue')).to eq(worker_class.to_s)
      expect(enqueue_span.get_tag('sucker_punch.perform_in')).to eq(0)
      expect(enqueue_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sucker_punch')
      expect(enqueue_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('perform_in')
    end
  end

  context 'keyword arguments' do
    # We do not want mocks or stubs here, as these would define their own
    # wrapper or replacement methods interfering with the argument passing
    # test, therefore we record behaviour data on a side-effect of an object.
    let(:recorded) { [] }

    let(:worker_class) do
      clazz = Class.new do
        include SuckerPunch::Job

        def perform(*args, required:)
          self.class.instance_variable_get(:@recorded) << [args, required]
        end
      end

      clazz.instance_variable_set(:@recorded, recorded)

      clazz
    end

    context 'internal call to job' do
      subject(:dummy_worker) { worker_class.__run_perform(1, required: 2) }
      let(:expect_thread?) { false }

      it 'passes kwargs correctly through instrumentation' do
        dummy_worker
        try_wait_until { recorded.any? }

        expect(recorded.first).to eq([[1], 2])
      end
    end

    context 'async job' do
      subject(:dummy_worker) { worker_class.perform_async(1, required: 2) }

      it 'passes kwargs correctly through instrumentation' do
        dummy_worker
        try_wait_until { recorded.any? }

        expect(recorded.first).to eq([[1], 2])
      end
    end

    context 'delayed job' do
      subject(:dummy_worker) { worker_class.perform_in(0, 1, required: 2) }

      it 'passes kwargs correctly through instrumentation' do
        dummy_worker
        try_wait_until { recorded.any? }

        expect(recorded.first).to eq([[1], 2])
      end
    end
  end
end
