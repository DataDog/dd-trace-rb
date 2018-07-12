require('time')
require('json')
require('spec_helper')
require('ddtrace/tracer')
require('ddtrace/workers')
require('ddtrace/writer')
require('ddtrace/pipeline')
require('support/test_access_patch')

RSpec.describe Datadog::Workers do
  HOSTNAME = 'http://127.0.0.1'.freeze
  PORT = 1234
  FLUSH_INTERVAL = 1
  BUFF_SIZE = 10
  before do
    @transport = SpyTransport.new(HOSTNAME, PORT)
    @writer = Datadog::Writer.new
    @writer.write([], {})
    @writer.stop
    @worker = Datadog::Workers::AsyncTransport.new(@transport,
                                                   BUFF_SIZE,
                                                   @writer.trace_handler,
                                                   @writer.service_handler,
                                                   FLUSH_INTERVAL)
    @writer.worker = @worker
    @writer.worker.start
    @tracer = Datadog::Tracer.new
    @tracer.configure(enabled: true, hostname: HOSTNAME, port: PORT)
    @tracer.writer = @writer
  end
  after { Datadog::Pipeline.processors = [] }

  describe 'span' do
    it('one span') do
      span = @tracer.start_span('my.op')
      span.service = 'my.service'
      sleep(0.001)
      span.finish
      (20 * FLUSH_INTERVAL).times do
        break if @writer.stats[:traces_flushed] >= 1
        sleep(0.1)
      end
      expect(@writer.stats[:traces_flushed]).to(eq(1))
      dump = @transport.helper_dump
      expect(dump[200]).not_to be_nil, 'no data for 200 OK'
      expect(dump[500]).not_to be_nil, 'no data for 500 OK'
      expect({}).to(eq(dump[500]))
      dumped_traces = dump[200][:traces]
      expect(dumped_traces).not_to be_nil, "no 200 OK data for default traces endpoint, dump: #{dump}"
      expect(dumped_traces.length).to(eq(1))
      expect(dumped_traces[0]).to be_a_kind_of(String)
      payload = JSON.parse(dumped_traces[0])
      expect(payload).to be_a_kind_of(Array)
      expect(payload.length).to(eq(1))
      trace = payload[0]
      expect(trace).to be_a_kind_of(Array)
      expect(trace.length).to(eq(1))
      span = trace[0]
      expect(span).to be_a_kind_of(Hash)
      expect(span['parent_id']).to(eq(0))
      expect(span['error']).to(eq(0))
      expect(span['span_id']).to_not(eq(span['trace_id']))
      expect(span['service']).to(eq('my.service'))
    end
    it('span default service') do
      span = @tracer.start_span('my.op')
      sleep(0.001)
      span.finish
      (20 * FLUSH_INTERVAL).times do
        break if @writer.stats[:traces_flushed] >= 1
        sleep(0.1)
      end
      expect(@writer.stats[:traces_flushed]).to(eq(1))
      dump = @transport.helper_dump
      dumped_traces = dump[200][:traces]
      expect(dumped_traces).not_to be_nil, 'no 200 OK data for default traces endpoint'
      expect(dumped_traces.length).to(eq(1))
      expect(dumped_traces[0]).to be_a_kind_of(String)
      payload = JSON.parse(dumped_traces[0])
      expect(payload).to be_a_kind_of(Array)
      expect(payload.length).to(eq(1))
      trace = payload[0]
      expect(trace).to be_a_kind_of(Array)
      expect(trace.length).to(eq(1))
      span = trace[0]
      expect(span).to be_a_kind_of(Hash)
      expect(span['parent_id']).to(eq(0))
      expect(span['error']).to(eq(0))
      expect(span['span_id']).to_not(eq(span['trace_id']))
      expect(span['service']).to(eq('rspec'))
    end
    it('span filtering') do
      filter = Datadog::Pipeline::SpanFilter.new { |span| span.name[/discard/] }
      Datadog::Pipeline.before_flush(filter)
      @tracer.start_span('keep', service: 'tracer-test').finish
      @tracer.start_span('discard', service: 'tracer-test').finish
      try_wait_until(attempts: 20) do
        @transport.helper_sent[200][:traces].any? rescue false
      end
      expect(@transport.helper_sent[200][:traces].to_s).to(match(/keep/))
      expect(@transport.helper_sent[200][:traces].to_s).not_to match(/discard/)
    end
  end

  describe 'service' do
    it('empty services') do
      span = @tracer.start_span('my.op')
      span.service = 'my.service'
      sleep(0.001)
      span.finish
      (20 * FLUSH_INTERVAL).times do |_i|
        break if @writer.stats[:traces_flushed] >= 1
        sleep(0.1)
      end
      expect(@writer.stats[:traces_flushed]).to(eq(1))
      sleep((2 * FLUSH_INTERVAL))
      expect(@writer.stats[:services_flushed]).to(eq(0))
    end
    it('two services') do
      @tracer.set_service_info('my.service', 'rails', 'web')
      @tracer.set_service_info('my.other.service', 'golang', 'api')
      @tracer.start_span('my.op').finish
      try_wait_until(attempts: 200, backoff: 0.1) do
        (@writer.stats[:services_flushed] >= 1)
      end
      expect(@writer.stats[:services_flushed]).to(eq(1))
      dump = @transport.helper_dump
      expect(dump[200]).not_to be_nil, 'no data for 200 OK'
      expect(dump[500]).not_to be_nil, 'no data for 500 OK'
      expect({}).to(eq(dump[500]))
      dumped_services = dump[200][:services]
      expect(dumped_services).not_to be_nil, 'no 200 OK data for default services endpoint'
      expect(dumped_services.length).to(eq(1))
      expect(dumped_services[0]).to be_a_kind_of(String)
      payload = JSON.parse(dumped_services[0])
      expect(payload).to be_a_kind_of(Hash)
      services = payload
      expect(services).to(eq('my.service' => { 'app' => 'rails', 'app_type' => 'web' },
                             'my.other.service' => { 'app' => 'golang', 'app_type' => 'api' }))
    end
  end

  context 'integration' do
    def generate_counter
      counter = []
      [counter, proc { (counter << :called) }]
    end

    LONG_INTERVAL = 10
    before do
      @trace_task_calls, trace_task = generate_counter
      @service_task_calls, service_task = generate_counter
      @worker = Datadog::Workers::AsyncTransport.new(nil, 100, trace_task, service_task, LONG_INTERVAL)
    end
    it('worker termination') do
      @worker.start
      sleep(0.5)
      @worker.enqueue_trace(get_test_traces(1))
      @worker.enqueue_service(get_test_services)
      expect(@trace_task_calls).to be_empty
      expect(@service_task_calls).to be_empty
      shutdown_beg = Time.now
      @worker.stop
      shutdown_end = Time.now
      expect(@trace_task_calls.count).to(eq(1))
      expect(@service_task_calls.count).to(eq(1))
      expect(((shutdown_end - shutdown_beg) < Datadog::Workers::AsyncTransport::SHUTDOWN_TIMEOUT)).to(be_truthy)
    end
    it('worker termination timeout') do
      task = proc { sleep(LONG_INTERVAL) }
      worker = Datadog::Workers::AsyncTransport.new(nil, 100, task, task, LONG_INTERVAL)
      worker.start
      sleep(0.5)
      worker.enqueue_trace(get_test_traces(1))
      worker.enqueue_service(get_test_services)
      shutdown_beg = Time.now
      worker.stop
      shutdown_end = Time.now
      expect(shutdown_end - shutdown_beg).to be_within(0.5).of(Datadog::Workers::AsyncTransport::SHUTDOWN_TIMEOUT)
    end
  end
end
