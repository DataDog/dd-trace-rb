require 'helper'
require 'ddtrace'
require 'ddtrace/tracer'
require 'thread'

# rubocop:disable Metrics/ClassLength
class TracerIntegrationTest < Minitest::Test
  def agent_receives_span_step1(tracer)
    stats = tracer.writer.stats
    assert_equal(0, stats[:traces_flushed])
    assert_equal(0, stats[:transport][:success])
    assert_equal(0, stats[:transport][:client_error])
    assert_equal(0, stats[:transport][:server_error])
    assert_equal(0, stats[:transport][:internal_error])
  end

  def agent_receives_span_step2(tracer)
    tracer.set_service_info('my.service', 'rails', 'web')

    span = tracer.start_span('my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    # timeout after 3 seconds, waiting for 1 flush
    test_repeat.times do
      break if tracer.writer.stats[:traces_flushed] >= 1
      sleep(0.1)
    end

    # timeout after 3 seconds, waiting for 1 flush
    test_repeat.times do
      break if tracer.writer.stats[:services_flushed] >= 1
      sleep(0.1)
    end

    stats = tracer.writer.stats
    assert_equal(1, stats[:traces_flushed], 'wrong number of traces flushed')
    assert_equal(1, stats[:services_flushed], 'wrong number of services flushed')
    # number of successes can be 1 or 2 because services count as one flush too
    assert_operator(1, :<=, stats[:transport][:success])
    assert_equal(0, stats[:transport][:client_error])
    assert_equal(0, stats[:transport][:server_error])
    assert_equal(0, stats[:transport][:internal_error])

    stats[:transport][:success]
  end

  def agent_receives_span_step3(tracer, previous_success)
    span = tracer.start_span('my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    # timeout after 3 seconds, waiting for another flush
    test_repeat.times do
      break if tracer.writer.stats[:traces_flushed] >= 2
      sleep(0.1)
    end

    stats = tracer.writer.stats
    assert_equal(2, stats[:traces_flushed], 'wrong number of traces flushed')
    assert_equal(1, stats[:services_flushed], 'wrong number of services flushed')
    assert_operator(previous_success, :<, stats[:transport][:success])
    assert_equal(0, stats[:transport][:client_error])
    assert_equal(0, stats[:transport][:server_error])
    assert_equal(0, stats[:transport][:internal_error])
  end

  def agent_receives_short_span(tracer)
    tracer.set_service_info('my.service', 'rails', 'web')
    span = tracer.start_span('my.short.op')
    span.service = 'my.service'
    span.finish()

    first_shutdown = tracer.shutdown!

    stats = tracer.writer.stats
    assert(first_shutdown, 'should have run through the shutdown method')
    assert(span.finished?, 'span did not finish')
    assert_equal(1, stats[:traces_flushed], 'wrong number of traces flushed')
    assert_equal(1, stats[:services_flushed], 'wrong number of services flushed')
    assert_equal(0, stats[:transport][:client_error])
    assert_equal(0, stats[:transport][:server_error])
    assert_equal(0, stats[:transport][:internal_error])
  end

  def shutdown_exec_only_once(tracer)
    tracer.set_service_info('my.service', 'rails', 'web')
    span = tracer.start_span('my.short.op')
    span.service = 'my.service'
    span.finish()
    mutex = Mutex.new
    shutdown_results = []

    threads = Array.new(10) do
      Thread.new { mutex.synchronize { shutdown_results << tracer.shutdown! } }
    end

    threads.each(&:join)

    stats = tracer.writer.stats
    assert_equal(1, shutdown_results.count(true), 'shutdown should have returned true only once')
    assert_equal(1, stats[:traces_flushed], 'wrong number of traces flushed')
    assert_equal(1, stats[:services_flushed], 'wrong number of services flushed')
    assert_equal(0, stats[:transport][:client_error])
    assert_equal(0, stats[:transport][:server_error])
    assert_equal(0, stats[:transport][:internal_error])
  end

  def test_agent_receives_span
    # test that the agent really receives the spans
    # this test can be long since it waits internal buffers flush
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent

    tracer = Datadog::Tracer.new
    tracer.configure(
      enabled: true,
      hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
      port: ENV.fetch('TEST_DDAGENT_PORT', 8126)
    )

    agent_receives_span_step1(tracer)
    success = agent_receives_span_step2(tracer)
    agent_receives_span_step3(tracer, success)
  end

  def test_short_span
    skip unless ENV['TEST_DATADOG_INTEGRATION'] || RUBY_PLATFORM != 'java'
    # requires a running agent, and test does not apply to Java threading model

    tracer = Datadog::Tracer.new
    tracer.configure(
      enabled: true,
      hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
      port: ENV.fetch('TEST_DDAGENT_PORT', 8126)
    )

    agent_receives_short_span(tracer)
  end

  def test_shutdown_exec_once
    skip unless ENV['TEST_DATADOG_INTEGRATION'] || RUBY_PLATFORM != 'java'
    # requires a running agent, and test does not apply to Java threading model

    tracer = Datadog::Tracer.new
    tracer.configure(
      enabled: true,
      hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
      port: ENV.fetch('TEST_DDAGENT_PORT', 8126)
    )

    shutdown_exec_only_once(tracer)
  end

  def test_sampling_priority_metric_propagation
    tracer = get_test_tracer
    tracer.configure(priority_sampling: true)
    tracer.writer = FauxWriter.new(priority_sampler: Datadog::PrioritySampler.new)

    span_a = tracer.start_span('span_a')
    span_b = tracer.start_span('span_b', child_of: span_a.context)

    # I want to keep the trace to which `span_b` belongs
    span_b.context.sampling_priority = 10

    span_b.finish
    span_a.finish

    try_wait_until { tracer.writer.spans(:keep).any? }

    # The root span should have the correct sampling priority metric
    assert_equal(
      10,
      span_a.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)
    )
  end

  def test_priority_sampling_integration
    # Whatever the sampling priority sampling is, all traces are sent to the agent,
    # the agent then sends it or not depending on the priority, but they are all sent.
    3.times do |i|
      tracer = Datadog::Tracer.new
      tracer.configure(
        enabled: true,
        hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
        port: ENV.fetch('TEST_DDAGENT_PORT', 8126),
        priority_sampling: true
      )

      span_a = tracer.start_span('span_a')
      span_b = tracer.start_span('span_b', child_of: span_a.context)

      # I want to keep the trace to which `span_b` belongs
      span_b.context.sampling_priority = i

      span_b.finish
      span_a.finish

      try_wait_until(attempts: 20) { tracer.writer.stats[:traces_flushed] >= 1 }
      stats = tracer.writer.stats

      assert_equal(1, stats[:traces_flushed], "wrong number of traces flushed [sampling_priority=#{i}]")
      assert_equal(0, stats[:transport][:client_error])
      assert_equal(0, stats[:transport][:server_error])
      assert_equal(0, stats[:transport][:internal_error])
    end
  end
end
