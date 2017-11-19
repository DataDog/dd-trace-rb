require 'time'
require 'json'

require 'helper'
require 'ddtrace/tracer'
require 'ddtrace/workers'
require 'ddtrace/writer'

class WorkersTest < Minitest::Test
  HOSTNAME = 'http://127.0.0.1'.freeze
  PORT = 1234
  FLUSH_INTERVAL = 1
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
    @worker = Datadog::Workers::AsyncTransport.new(@transport,
                                                   BUFF_SIZE,
                                                   @writer.trace_handler,
                                                   @writer.service_handler,
                                                   FLUSH_INTERVAL)
    @writer.worker = @worker
    @writer.worker.start()
    # at this stage our custom writer is in place, bind it to a tracer
    @tracer = Datadog::Tracer.new
    @tracer.configure(enabled: true, hostname: HOSTNAME, port: PORT)
    @tracer.writer = @writer
  end

  def teardown
    Datadog::Pipeline.processors = []
  end
end

class WorkersSpanTest < WorkersTest
  # test that one single span, in the most simple case, is correctly handled.
  # this is not purely an intergration test as it does not rely on a real agent
  # but it checks that all the machinery around workers (tracer/writer/worker/transport)
  # is consistent and that data flows through it.
  def test_one_span
    span = @tracer.start_span('my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    (20 * FLUSH_INTERVAL).times do
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
    refute_nil(dumped_traces, "no 200 OK data for default traces endpoint, dump: #{dump}")
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
    refute_equal(span['trace_id'], span['span_id'], 'trace_id and span_id are different for any span')
    assert_equal('my.service', span['service'], 'wrong service')
  end

  # test that a default service is provided if none has been given at all
  def test_span_default_service
    span = @tracer.start_span('my.op')
    sleep(0.001)
    span.finish()

    (20 * FLUSH_INTERVAL).times do
      break if @writer.stats[:traces_flushed] >= 1
      sleep(0.1)
    end

    assert_equal(1, @writer.stats[:traces_flushed], 'wrong number of traces flushed')
    dump = @transport.helper_dump
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
    refute_equal(span['trace_id'], span['span_id'], 'trace_id and span_id are different for any span')
    # now the whole purpose of this test: check we have a 'ruby' service by default,
    # which should be guessed from the script being executed.
    assert_equal('rake_test_loader', span['service'], 'wrong service')
  end

  def test_span_filtering
    filter = Datadog::Pipeline::SpanFilter.new do |span|
      span.name[/discard/]
    end

    Datadog::Pipeline.before_flush(filter)

    @tracer.start_span('keep', service: 'tracer-test').finish
    @tracer.start_span('discard', service: 'tracer-test').finish

    try_wait_until(attempts: 20) do
      @transport.helper_sent[200][:traces].any? rescue false
    end

    assert_match(/keep/, @transport.helper_sent[200][:traces].to_s)
    refute_match(/discard/, @transport.helper_sent[200][:traces].to_s)
  end
end

class WorkersServiceTest < WorkersTest
  # test that services are not flushed, when empty
  def test_empty_services
    span = @tracer.start_span('my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish()

    (20 * FLUSH_INTERVAL).times do |_i|
      break if @writer.stats[:traces_flushed] >= 1
      sleep(0.1)
    end

    assert_equal(1, @writer.stats[:traces_flushed], 'wrong number of traces flushed')
    sleep(2 * FLUSH_INTERVAL)
    assert_equal(0, @writer.stats[:services_flushed], 'wrong number of services flushed')
  end

  # test that services are correctly flushed, with two of them
  def test_two_services
    @tracer.set_service_info('my.service', 'rails', 'web')
    @tracer.set_service_info('my.other.service', 'golang', 'api')
    @tracer.start_span('my.op').finish

    try_wait_until(attempts: 200, backoff: 0.1) do
      @writer.stats[:services_flushed] >= 1
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
end

class WorkerIntegrationTest < Minitest::Test
  LONG_INTERVAL = 10

  def setup
    @trace_task_calls, trace_task = generate_counter
    @service_task_calls, service_task = generate_counter

    @worker = Datadog::Workers::AsyncTransport.new(nil, 100, trace_task, service_task, LONG_INTERVAL)
  end

  def test_worker_termination
    @worker.start

    # let it reach the 10 seconds back-off
    sleep(0.5)

    # enqueue some work for a final flush
    @worker.enqueue_trace(get_test_traces(1))
    @worker.enqueue_service(get_test_services)

    # make sure we have a consistent test set-up
    assert_empty(@trace_task_calls)
    assert_empty(@service_task_calls)

    # interrupt back off and flush everything immeditiately
    shutdown_beg = Time.now
    @worker.stop
    shutdown_end = Time.now

    assert_equal(1, @trace_task_calls.count)
    assert_equal(1, @service_task_calls.count)
    assert((shutdown_end - shutdown_beg) < Datadog::Workers::AsyncTransport::SHUTDOWN_TIMEOUT)
  end

  def test_worker_termination_timeout
    task = proc { sleep(LONG_INTERVAL) }
    worker = Datadog::Workers::AsyncTransport.new(nil, 100, task, task, LONG_INTERVAL)

    worker.start

    # let it reach the 10 seconds back-off
    sleep(0.5)

    worker.enqueue_trace(get_test_traces(1))
    worker.enqueue_service(get_test_services)

    shutdown_beg = Time.now
    worker.stop
    shutdown_end = Time.now

    assert_in_delta(Datadog::Workers::AsyncTransport::SHUTDOWN_TIMEOUT, shutdown_end - shutdown_beg, 0.5)
  end

  private

  def generate_counter
    counter = []

    [
      counter,
      proc { counter << :called }
    ]
  end
end
p
