require 'spec_helper'

require 'ddtrace'
require 'ddtrace/tracer'
require 'thread'

RSpec.describe 'Tracer integration tests' do
  include_context 'transport metrics'

  shared_context 'agent-based test' do
    before(:each) { skip unless ENV['TEST_DATADOG_INTEGRATION'] }

    let(:tracer) do
      Datadog::Tracer.new.tap do |t|
        t.configure(
          enabled: true,
          hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
          port: ENV.fetch('TEST_DDAGENT_TRACE_PORT', 8126),
          statsd: statsd
        )
      end
    end
  end

  def expect_no_error_metrics
    expect(statsd).to_not have_received_increment_transport_metric(
      Datadog::HTTPTransport::METRIC_RESPONSE,
      tags: ["#{Datadog::Ext::HTTP::STATUS_CODE}:400"]
    )

    expect(statsd).to_not have_received_increment_transport_metric(
      Datadog::HTTPTransport::METRIC_RESPONSE,
      tags: ["#{Datadog::Ext::HTTP::STATUS_CODE}:500"]
    )

    expect(statsd).to_not have_received_increment_transport_metric(
      Datadog::HTTPTransport::METRIC_INTERNAL_ERROR,
      any_args
    )
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
      try_wait_until(attempts: 30) { stats[stat] >= num }
    end

    def agent_receives_span_step1
      expect(stats[Datadog::Writer::METRIC_TRACES_FLUSHED]).to eq(0)
      expect(statsd).to_not have_received_increment_transport_metric(
        Datadog::HTTPTransport::METRIC_RESPONSE,
        tags: ["#{Datadog::Ext::HTTP::STATUS_CODE}:200"]
      )
      expect_no_error_metrics
    end

    def agent_receives_span_step2
      tracer.set_service_info('my.service', 'rails', 'web')

      create_trace

      wait_for_flush(Datadog::Writer::METRIC_TRACES_FLUSHED)
      wait_for_flush(Datadog::Writer::METRIC_SERVICES_FLUSHED)

      expect(stats[Datadog::Writer::METRIC_TRACES_FLUSHED]).to eq(1)
      expect(stats[Datadog::Writer::METRIC_SERVICES_FLUSHED]).to eq(1)

      # Number of successes counts both traces and services
      expect(statsd).to have_received_increment_transport_metric(
        Datadog::HTTPTransport::METRIC_RESPONSE,
        tags: [Datadog::Ext::Metrics::TAG_DATA_TYPE_TRACES, "#{Datadog::Ext::HTTP::STATUS_CODE}:200"]
      ).once
      expect(statsd).to have_received_increment_transport_metric(
        Datadog::HTTPTransport::METRIC_RESPONSE,
        tags: [Datadog::Ext::Metrics::TAG_DATA_TYPE_SERVICES, "#{Datadog::Ext::HTTP::STATUS_CODE}:200"]
      ).once
      expect_no_error_metrics
    end

    def agent_receives_span_step3
      create_trace

      wait_for_flush(Datadog::Writer::METRIC_TRACES_FLUSHED, 2)

      # Trace flushes should increment, services should not.
      expect(stats[Datadog::Writer::METRIC_TRACES_FLUSHED]).to eq(2)
      expect(stats[Datadog::Writer::METRIC_SERVICES_FLUSHED]).to eq(1)

      expect(statsd).to have_received_increment_transport_metric(
        Datadog::HTTPTransport::METRIC_RESPONSE,
        tags: [Datadog::Ext::Metrics::TAG_DATA_TYPE_TRACES, "#{Datadog::Ext::HTTP::STATUS_CODE}:200"]
      ).exactly(2).times
      expect_no_error_metrics
    end

    it do
      agent_receives_span_step1
      agent_receives_span_step2
      agent_receives_span_step3
    end
  end

  describe 'agent receives short span' do
    include_context 'agent-based test'

    before(:each) do
      tracer.set_service_info('my.service', 'rails', 'web')

      tracer.trace('my.short.op') do |span|
        @span = span
        span.service = 'my.service'
      end

      @first_shutdown = tracer.shutdown!
    end

    it do
      expect(@first_shutdown).to be true
      expect(@span.finished?).to be true
      expect(statsd).to have_received_increment_metric(Datadog::Writer::METRIC_TRACES_FLUSHED, by: 1)
      expect(statsd).to have_received_increment_metric(Datadog::Writer::METRIC_SERVICES_FLUSHED)
      expect_no_error_metrics
    end
  end

  describe 'shutdown executes only once' do
    include_context 'agent-based test'

    before(:each) do
      tracer.set_service_info('my.service', 'rails', 'web')

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

    it do
      expect(@shutdown_results.count(true)).to eq(1)
      expect(statsd).to have_received_increment_metric(Datadog::Writer::METRIC_TRACES_FLUSHED, by: 1)
      expect(statsd).to have_received_increment_metric(Datadog::Writer::METRIC_SERVICES_FLUSHED)
      expect_no_error_metrics
    end
  end

  describe 'sampling priority metrics' do
    let(:tracer) do
      get_test_tracer.tap do |t|
        t.configure(priority_sampling: true)
        t.writer = writer
      end
    end

    let(:writer) { FauxWriter.new(priority_sampler: Datadog::PrioritySampler.new) }

    context 'when #sampling_priority is set on a child span' do
      let(:parent_span) { tracer.start_span('parent span') }
      let(:child_span) { tracer.start_span('child span', child_of: parent_span.context) }

      before(:each) do
        parent_span.tap do
          child_span.tap do
            child_span.context.sampling_priority = 10
          end.finish
        end.finish

        try_wait_until(attempts: 30) { writer.spans(:keep).any? }
      end

      it do
        metric_value = parent_span.get_metric(
          Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY
        )

        expect(metric_value).to eq(10)
      end
    end
  end

  describe 'sampling priority integration' do
    include_context 'agent-based test'

    before(:each) do
      tracer.configure(
        enabled: true,
        hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
        port: ENV.fetch('TEST_DDAGENT_TRACE_PORT', 8126),
        priority_sampling: true,
        statsd: statsd
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

        try_wait_until(attempts: 30) { stats[Datadog::Writer::METRIC_TRACES_FLUSHED] >= i + 1 }

        expect(stats[Datadog::Writer::METRIC_TRACES_FLUSHED]).to eq(i + 1)
        expect(statsd).to have_received_time_metric(
          Datadog::Writer::METRIC_SAMPLING_UPDATE_TIME,
          tags: [Datadog::Ext::Metrics::TAG_PRIORITY_SAMPLING_ENABLED]
        ).exactly(i + 1).times
        expect_no_error_metrics
      end
    end
  end
end
