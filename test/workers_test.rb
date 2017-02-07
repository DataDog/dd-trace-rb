require 'time'
require 'json'

require 'helper'
require 'ddtrace/tracer'
require 'ddtrace/workers'
require 'ddtrace/writer'

class WorkersTest < Minitest::Test
  HOSTNAME = 'http://127.0.0.1'.freeze
  PORT = 1234
  SPAN_INTERVAL = 1
  SERVICE_INTERVAL = 3
  BUFF_SIZE = 10

  def setup
    # create a standard tracer and patch its worker
    # so that we can spy on what's sent to transport

    # first, our home made transport, to get feedback
    @transport = SpyTransport.new(HOSTNAME, PORT)
    @writer = Datadog::Writer.new
    @writer.write([], {}) # write some stuff to trigger a start()
    # now stop the writer and replace worker with ours, if we don't do
    # this the old worder will still be used.
    @writer.stop()
    @worker = Datadog::Workers::AsyncTransport.new(SPAN_INTERVAL,
                                                   SERVICE_INTERVAL,
                                                   @transport,
                                                   BUFF_SIZE,
                                                   @writer.trace_handler,
                                                   @writer.service_handler)
    @writer.worker = @worker
    @writer.worker.start()
    # at this stage our custom writer is in place, bind it to a tracer
    @tracer = Datadog::Tracer.new
    @tracer.configure(enabled: true, hostname: HOSTNAME, port: PORT)
    @tracer.writer = @writer
  end
end

class WorkersSpanTest < WorkersTest
  # test that one single span, in the most simple case, is correctly handled.
  # this is not purely an intergration test as it does not rely on a real agent
  # but it checks that all the machinery around workers (tracer/writer/worker/transport)
  # is consistent and that data flows through it.
  def test_one_span
    span = Datadog::Span.new(@tracer, 'my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    (20 * SPAN_INTERVAL).times do
      break if @writer.stats[:traces_flushed] >= 1
      sleep(0.1)
    end

    assert_equal(1, @writer.stats[:traces_flushed], 'wrong number of traces flushed')

    dump = @transport.helper_dump
    # sanity checks
    refute_nil(dump[200], 'no data for 200 OK')
    refute_nil(dump[500], 'no data for 500 OK')
    assert_equal(dump[500], {}, '500 ERROR')
    dumped_traces = dump[200][:traces]
    refute_nil(dumped_traces, 'no 200 OK data for default traces endpoint')
    # unmarshalling data
    assert_equal(1, dumped_traces.length, 'there should be one and only one payload')
    assert_kind_of(String, dumped_traces[0])
    payload = JSON.parse(dumped_traces[0])
    assert_kind_of(Array, payload)
    assert_equal(1, payload.length, 'there should be one trace in the payload')
    trace = payload[0]
    assert_kind_of(Array, trace)
    assert_equal(1, trace.length, 'there should be one span in the trace')
    span = trace[0]
    assert_kind_of(Hash, span)
    # checking content
    assert_equal(0, span['parent_id'], 'a root span should have no parent')
    assert_equal(0, span['error'], 'there should be explicitely no error')
    assert_equal(span['trace_id'], span['span_id'], 'a root span should have equal trace_id and span_id')
    assert_equal('my.service', span['service'], 'wrong service')
  end

  # test that retry on failure works for traces
  def test_span_retry
    span = Datadog::Span.new(@tracer, 'my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    (20 * SPAN_INTERVAL).times do
      break if @writer.stats[:traces_flushed] >= 1
      sleep(0.1)
    end

    assert_equal(1, @writer.stats[:traces_flushed], 'wrong number of traces flushed')

    @transport.helper_error_mode! true # now responding 500 ERROR

    span = Datadog::Span.new(@tracer, 'my.op2')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    sleep(2 * SPAN_INTERVAL) # wait long enough so that a flush happens

    assert_equal(1, @writer.stats[:traces_flushed], 'wrong number of traces flushed')

    @transport.helper_error_mode! false # now responding 200 OK

    (20 * SPAN_INTERVAL).times do
      break if @writer.stats[:traces_flushed] >= 2
      sleep(0.1)
    end

    assert_operator(2, :<=, @writer.stats[:traces_flushed], 'wrong number of traces flushed')

    dump = @transport.helper_dump
    dumped_traces = dump[500][:traces]
    assert_operator(1, :<=, dumped_traces.length, 'there should have been errors on traces endpoint')
  end
end

class WorkersServiceTest < WorkersTest
  # test that services are not flushed, when empty
  def test_empty_services
    span = Datadog::Span.new(@tracer, 'my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    sleep(2 * SERVICE_INTERVAL)

    (20 * SPAN_INTERVAL).times do
      break if @writer.stats[:traces_flushed] >= 1
      sleep(0.1)
    end

    assert_equal(1, @writer.stats[:traces_flushed], 'wrong number of traces flushed')
    assert_equal(0, @writer.stats[:services_flushed], 'wrong number of services flushed')
  end

  # test that services are correctly flushed, with two of them
  def test_two_services
    @tracer.set_service_info('my.service', 'rails', 'web')
    @tracer.set_service_info('my.other.service', 'golang', 'api')

    span = Datadog::Span.new(@tracer, 'my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    (20 * SERVICE_INTERVAL).times do
      break if @writer.stats[:services_flushed] >= 1
      sleep(0.1)
    end

    assert_equal(1, @writer.stats[:services_flushed], 'wrong number of services flushed')

    dump = @transport.helper_dump
    # sanity checks
    refute_nil(dump[200], 'no data for 200 OK')
    refute_nil(dump[500], 'no data for 500 OK')
    assert_equal(dump[500], {}, '500 ERROR')
    dumped_services = dump[200][:services]
    refute_nil(dumped_services, 'no 200 OK data for default services endpoint')
    # unmarshalling data
    assert_equal(1, dumped_services.length, 'there should be one and only one payload')
    assert_kind_of(String, dumped_services[0])
    payload = JSON.parse(dumped_services[0])
    assert_kind_of(Hash, payload)
    services = payload
    # checking content
    assert_equal({ 'my.service' => { 'app' => 'rails', 'app_type' => 'web' },
                   'my.other.service' => { 'app' => 'golang', 'app_type' => 'api' } },
                 services, 'bad services metadata')
  end

  # test that retry on failure works for services
  def test_service_retry
    @tracer.set_service_info('my.service', 'rails', 'web')

    span = Datadog::Span.new(@tracer, 'my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    (20 * SERVICE_INTERVAL).times do
      break if @writer.stats[:services_flushed] >= 1
      sleep(0.1)
    end

    assert_equal(1, @writer.stats[:services_flushed], 'wrong number of services flushed')

    @transport.helper_error_mode! true # now responding 500 ERROR

    @tracer.set_service_info('my.other.service', 'golang', 'api')
    @tracer.set_service_info('my.yet.other.service', 'postgresql', 'sql')

    # need to generate a trace else service info does not make it to the queue
    span = Datadog::Span.new(@tracer, 'my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    sleep(2 * SERVICE_INTERVAL) # wait long enough so that a flush happens

    # nothing happens (500 ERROR...)
    assert_equal(1, @writer.stats[:services_flushed], 'wrong number of services flushed')

    @transport.helper_error_mode! false # now responding 200 OK

    (20 * SERVICE_INTERVAL).times do
      break if @writer.stats[:services_flushed] >= 2
      sleep(0.1)
    end

    assert_equal(2, @writer.stats[:services_flushed], 'wrong number of services flushed')

    dump = @transport.helper_dump
    dumped_services = dump[500][:services]
    assert_operator(1, :<=, dumped_services.length, 'there should have been errors on services endpoint')
  end
end
