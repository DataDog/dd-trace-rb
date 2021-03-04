require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'sucker_punch'
require 'ddtrace'

RSpec.describe 'sucker_punch instrumentation' do
  before do
    Datadog.configure do |c|
      c.use :sucker_punch
    end

    SuckerPunch::RUNNING.make_true
  end

  after do
    count = Thread.list.size

    SuckerPunch::RUNNING.make_false
    SuckerPunch::Queue.all.each(&:shutdown)
    SuckerPunch::Queue.clear

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
        try_wait_until { fetch_spans.any? }
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

      expect(job_span.service).to eq('sucker_punch')
      expect(job_span.name).to eq('sucker_punch.perform')
      expect(job_span.resource).to eq("PROCESS #{worker_class}")
      expect(job_span.get_tag('sucker_punch.queue')).to eq(worker_class.to_s)
      expect(job_span.status).not_to eq(Datadog::Ext::Errors::STATUS)
    end

    it 'instruments successful enqueuing' do
      is_expected.to be true
      try_wait_until { fetch_spans.any? }

      expect(enqueue_span.service).to eq('sucker_punch')
      expect(enqueue_span.name).to eq('sucker_punch.perform_async')
      expect(enqueue_span.resource).to eq("ENQUEUE #{worker_class}")
      expect(enqueue_span.get_tag('sucker_punch.queue')).to eq(worker_class.to_s)
      expect(enqueue_span.get_metric('_dd.measured')).to eq(1.0)
    end
  end

  context 'failed job' do
    subject(:dummy_worker_fail) { worker_class.perform_async(:fail) }

    let(:job_span) { spans.find { |s| s.resource[/PROCESS/] } }
    let(:span) { spans.first }

    it_behaves_like 'measured span for integration', true do
      before do
        dummy_worker_fail
        try_wait_until { fetch_spans.any? }
      end
    end

    it 'instruments a failed job' do
      is_expected.to be true
      try_wait_until { fetch_spans.length == 2 }

      expect(job_span.service).to eq('sucker_punch')
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
        try_wait_until { fetch_spans.any? }
      end
    end

    it 'instruments enqueuing for a delayed job' do
      dummy_worker_delay
      try_wait_until { fetch_spans.any? }

      expect(enqueue_span.service).to eq('sucker_punch')
      expect(enqueue_span.name).to eq('sucker_punch.perform_in')
      expect(enqueue_span.resource).to eq("ENQUEUE #{worker_class}")
      expect(enqueue_span.get_tag('sucker_punch.queue')).to eq(worker_class.to_s)
      expect(enqueue_span.get_tag('sucker_punch.perform_in')).to eq(0)
    end
  end
end
