require 'spec_helper'

require 'ddtrace'
require 'ddtrace/tracer'
require 'thread'

RSpec.describe 'Tracer integration tests' do
  shared_context 'agent-based test' do
    before(:each) { skip unless ENV['TEST_DATADOG_INTEGRATION'] }

    let(:tracer) do
      Datadog::Tracer.new.tap do |t|
        t.configure(
          enabled: true
        )
      end
    end
  end

  describe 'agent receives span' do
    include_context 'agent-based test'

    def create_trace
      tracer.trace('my.op') do |span|
        span.service = 'my.service'
        sleep(0.001)
      end
    end

    def wait_for_flush(stat, num = 1)
      test_repeat.times do
        break if tracer.writer.stats[stat] >= num
        sleep(0.1)
      end
    end

    def agent_receives_span_step1
      stats = tracer.writer.stats
      expect(stats[:traces_flushed]).to eq(0)
      expect(stats[:transport][:success]).to eq(0)
      expect(stats[:transport][:client_error]).to eq(0)
      expect(stats[:transport][:server_error]).to eq(0)
      expect(stats[:transport][:internal_error]).to eq(0)
    end

    def agent_receives_span_step2
      create_trace

      # Timeout after 3 seconds, waiting for 1 flush
      wait_for_flush(:traces_flushed)

      stats = tracer.writer.stats
      expect(stats[:traces_flushed]).to eq(1)
      expect(stats[:services_flushed]).to be_nil
      # Number of successes will only be 1 since we do not flush services
      expect(stats[:transport][:success]).to eq(1)
      expect(stats[:transport][:client_error]).to eq(0)
      expect(stats[:transport][:server_error]).to eq(0)
      expect(stats[:transport][:internal_error]).to eq(0)

      stats[:transport][:success]
    end

    def agent_receives_span_step3(previous_success)
      create_trace

      # Timeout after 3 seconds, waiting for another flush
      wait_for_flush(:traces_flushed, 2)

      stats = tracer.writer.stats
      expect(stats[:traces_flushed]).to eq(2)
      expect(stats[:services_flushed]).to be_nil
      expect(stats[:transport][:success]).to be > previous_success
      expect(stats[:transport][:client_error]).to eq(0)
      expect(stats[:transport][:server_error]).to eq(0)
      expect(stats[:transport][:internal_error]).to eq(0)
    end

    it do
      agent_receives_span_step1
      success = agent_receives_span_step2
      agent_receives_span_step3(success)
    end
  end

  describe 'agent receives short span' do
    include_context 'agent-based test'

    before(:each) do
      tracer.trace('my.short.op') do |span|
        @span = span
        span.service = 'my.service'
      end

      @first_shutdown = tracer.shutdown!
    end

    let(:stats) { tracer.writer.stats }

    it do
      expect(@first_shutdown).to be true
      expect(@span.finished?).to be true
      expect(stats[:traces_flushed]).to eq(1)
      expect(stats[:services_flushed]).to be_nil
      expect(stats[:transport][:client_error]).to eq(0)
      expect(stats[:transport][:server_error]).to eq(0)
      expect(stats[:transport][:internal_error]).to eq(0)
    end
  end

  describe 'shutdown executes only once' do
    include_context 'agent-based test'

    before(:each) do
      tracer.trace('my.short.op') do |span|
        span.service = 'my.service'
      end

      mutex = Mutex.new
      @shutdown_results = []

      threads = Array.new(10) do
        Thread.new { mutex.synchronize { @shutdown_results << tracer.shutdown! } }
      end

      threads.each(&:join)
    end

    let(:stats) { tracer.writer.stats }

    it do
      expect(@shutdown_results.count(true)).to eq(1)
      expect(stats[:traces_flushed]).to eq(1)
      expect(stats[:services_flushed]).to be_nil
      expect(stats[:transport][:client_error]).to eq(0)
      expect(stats[:transport][:server_error]).to eq(0)
      expect(stats[:transport][:internal_error]).to eq(0)
    end
  end

  describe 'sampling priority metrics' do
    # Sampling priority is enabled by default
    let(:tracer) { get_test_tracer }

    context 'when #sampling_priority is set on a child span' do
      let(:parent_span) { tracer.start_span('parent span') }
      let(:child_span) { tracer.start_span('child span', child_of: parent_span.context) }

      before(:each) do
        parent_span.tap do
          child_span.tap do
            child_span.context.sampling_priority = 10
          end.finish
        end.finish

        try_wait_until { tracer.writer.spans(:keep).any? }
      end

      it do
        metric_value = parent_span.get_metric(
          Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY
        )

        expect(metric_value).to eq(10)
      end
    end
  end

  describe 'origin tag' do
    # Sampling priority is enabled by default
    let(:tracer) { get_test_tracer }

    context 'when #sampling_priority is set on a parent span' do
      subject(:tag_value) { parent_span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY) }
      let(:parent_span) { tracer.start_span('parent span') }

      before(:each) do
        parent_span.tap do
          parent_span.context.origin = 'synthetics'
        end.finish

        try_wait_until { tracer.writer.spans(:keep).any? }
      end

      it { is_expected.to eq('synthetics') }
    end
  end

  describe 'sampling priority integration' do
    include_context 'agent-based test'

    before(:each) do
      tracer.configure(
        enabled: true,
        priority_sampling: true
      )
    end

    it do
      3.times do |i|
        parent_span = tracer.start_span('parent_span')
        child_span = tracer.start_span('child_span', child_of: parent_span.context)

        # I want to keep the trace to which `child_span` belongs
        child_span.context.sampling_priority = i

        child_span.finish
        parent_span.finish

        try_wait_until(attempts: 20) { tracer.writer.stats[:traces_flushed] >= 1 }
        stats = tracer.writer.stats

        expect(stats[:traces_flushed]).to eq(1)
        expect(stats[:transport][:client_error]).to eq(0)
        expect(stats[:transport][:server_error]).to eq(0)
        expect(stats[:transport][:internal_error]).to eq(0)
      end
    end
  end
end
