require 'helper'
require 'ddtrace'
require 'ddtrace/tracer'
require 'thread'

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

    tracer.shutdown!

    stats = tracer.writer.stats
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

    first_point = Time.now.utc
    tracer.shutdown!
    second_point = Time.now.utc
    tracer.shutdown!
    third_point = Time.now.utc

    first_shutdown = second_point - first_point
    second_shutdown = third_point - second_point

    stats = tracer.writer.stats
    assert(first_shutdown >= 0.1, 'should have executed shutdown')
    assert_equal(true, second_shutdown < 0.1, 'should not have executed second shutdown')
    assert_equal(true, span.finished?, 'span did not finish')
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
    tracer.configure(enabled: true, hostname: '127.0.0.1', port: '8126')

    agent_receives_span_step1(tracer)
    success = agent_receives_span_step2(tracer)
    agent_receives_span_step3(tracer, success)
  end

  def test_short_span
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent

    tracer = Datadog::Tracer.new
    tracer.configure(enabled: true, hostname: '127.0.0.1', port: '8126')

    agent_receives_short_span(tracer)
  end

  def test_shutdown_exec_once
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent

    tracer = Datadog::Tracer.new
    tracer.configure(enabled: true, hostname: '127.0.0.1', port: '8126')

    shutdown_exec_only_once(tracer)
  end
end
