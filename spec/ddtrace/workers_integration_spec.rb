require 'spec_helper'

require 'time'
require 'json'

require 'ddtrace/tracer'
require 'ddtrace/workers'
require 'ddtrace/writer'
require 'ddtrace/pipeline'

RSpec.describe 'Datadog::Workers::AsyncTransport integration tests' do
  include_context 'metric counts'

  let(:hostname) { 'http://127.0.0.1' }
  let(:port) { 1234 }
  let(:flush_interval) { 0.1 }
  let(:buffer_size) { 10 }

  let(:tracer) do
    Datadog::Tracer.new.tap do |t|
      t.configure(enabled: true, hostname: hostname, port: port)
      t.writer = writer
    end
  end

  let(:writer) do
    Datadog::Writer.new.tap do |w|
      # write some stuff to trigger a #start
      w.write([], {})
      # now stop the writer and replace worker with ours, if we don't do
      # this the old worker will still be used.
      w.stop
      w.instance_variable_set(
        :@worker,
        Datadog::Workers::AsyncTransport.new(
          transport,
          buffer_size,
          w.instance_variable_get(:@trace_handler),
          w.instance_variable_get(:@service_handler),
          flush_interval
        )
      )
      w.statsd = statsd
      w.worker.start
    end
  end

  let(:transport) { SpyTransport.new }

  let(:dump) { transport.helper_dump }

  describe 'when sending spans' do
    let(:dumped_traces) { dump[200][:traces] }
    let(:trace_payload) { JSON.parse(dumped_traces[0]) }
    let(:trace) { trace_payload[0] }
    let(:dumped_span) { trace[0] }

    # Test that one single span, in the most simple case, is correctly handled.
    # this is not purely an intergration test as it does not rely on a real agent
    # but it checks that all the machinery around workers (tracer/writer/worker/transport)
    # is consistent and that data flows through it.
    context 'with service names' do
      before(:each) do
        tracer.start_span('my.op').tap do |s|
          s.service = 'my.service'
          sleep(0.001)
          s.finish
        end

        try_wait_until(attempts: 30) { stats[Datadog::Writer::METRIC_TRACES_FLUSHED] >= 1 }
      end

      it 'flushes the trace correctly' do
        expect(stats[Datadog::Writer::METRIC_TRACES_FLUSHED]).to be >= 1
        expect(stats[Datadog::Writer::METRIC_SERVICES_FLUSHED]).to eq(0)

        # Sanity checks
        expect(dump[200]).to_not be nil
        expect(dump[500]).to_not be nil
        expect(dump[500]).to eq({})
        expect(dumped_traces).to_not be nil

        # Unmarshalling data
        expect(dumped_traces).to have(1).items
        expect(dumped_traces[0]).to be_a_kind_of(String)
        expect(trace_payload).to be_a_kind_of(Array)
        expect(trace_payload).to have(1).items
        expect(trace).to be_a_kind_of(Array)
        expect(trace).to have(1).items
        expect(dumped_span).to be_a_kind_of(Hash)

        # Checking content
        expect(dumped_span['parent_id']).to eq(0)
        expect(dumped_span['error']).to eq(0)
        expect(dumped_span['trace_id']).to_not eq(dumped_span['span_id'])
        expect(dumped_span['service']).to eq('my.service')
      end
    end

    # Test that a default service is provided if none has been given at all
    context 'with default service names' do
      before(:each) do
        tracer.start_span('my.op').tap do |s|
          sleep(0.001)
          s.finish
        end

        try_wait_until(attempts: 30) { stats[Datadog::Writer::METRIC_TRACES_FLUSHED] >= 1 }
      end

      it 'flushes the trace correctly' do
        expect(stats[Datadog::Writer::METRIC_TRACES_FLUSHED]).to be >= 1

        # Sanity checks
        expect(dump[200]).to_not be nil
        expect(dumped_traces).to_not be nil

        # Unmarshalling data
        expect(dumped_traces).to have(1).items
        expect(dumped_traces[0]).to be_a_kind_of(String)
        expect(trace_payload).to be_a_kind_of(Array)
        expect(trace_payload).to have(1).items
        expect(trace).to be_a_kind_of(Array)
        expect(trace).to have(1).items
        expect(dumped_span).to be_a_kind_of(Hash)

        # Checking content
        expect(dumped_span['parent_id']).to eq(0)
        expect(dumped_span['error']).to eq(0)
        expect(dumped_span['trace_id']).to_not eq(dumped_span['span_id'])
        expect(dumped_span['service']).to eq('rspec')
      end
    end

    context 'that are filtered' do
      before(:each) do
        # Activate filter
        filter = Datadog::Pipeline::SpanFilter.new do |span|
          span.name[/discard/]
        end

        Datadog::Pipeline.before_flush(filter)

        # Create spans
        tracer.start_span('keep', service: 'tracer-test').finish
        tracer.start_span('discard', service: 'tracer-test').finish

        try_wait_until(attempts: 30) { stats[Datadog::Writer::METRIC_TRACES_FLUSHED] >= 2 }
      end

      after(:each) { Datadog::Pipeline.processors = [] }

      it 'filters the trace correctly' do
        expect(transport.helper_sent[200][:traces].to_s).to match(/keep/)
        expect(transport.helper_sent[200][:traces].to_s).to_not match(/discard/)
      end
    end
  end

  describe 'when setting service info' do
    let(:dumped_services) { dump[200][:services] }
    let(:service_payload) { JSON.parse(dumped_services[0]) }

    # Test that services are correctly flushed, with two of them
    context 'for two services' do
      before(:each) do
        tracer.set_service_info('my.service', 'rails', 'web')
        tracer.set_service_info('my.other.service', 'golang', 'api')
        tracer.start_span('my.op').finish

        try_wait_until(attempts: 30) { stats[Datadog::Writer::METRIC_SERVICES_FLUSHED] >= 1 }
      end

      it 'flushes the services correctly' do
        expect(stats[Datadog::Writer::METRIC_SERVICES_FLUSHED]).to eq(1)

        # Sanity checks
        expect(dump[200]).to_not be nil
        expect(dump[500]).to_not be nil
        expect(dump[500]).to eq({})
        expect(dumped_services).to_not be nil

        # Unmarshalling data
        expect(dumped_services).to have(1).items
        expect(dumped_services[0]).to be_a_kind_of(String)
        expect(service_payload).to be_a_kind_of(Hash)

        expect(service_payload).to eq(
          'my.service' => { 'app' => 'rails', 'app_type' => 'web' },
          'my.other.service' => { 'app' => 'golang', 'app_type' => 'api' }
        )
      end
    end
  end

  describe 'when terminating the worker' do
    before(:each) do
      worker.start

      # Let it reach the 10 seconds back-off
      sleep(0.5)

      # Enqueue some work for a final flush
      worker.enqueue_trace(get_test_traces(1))
      worker.enqueue_service(get_test_services)

      # Interrupt back off and flush everything immediately
      @shutdown_beg = Time.now
      worker.stop
      @shutdown_end = Time.now
    end

    let(:worker) do
      Datadog::Workers::AsyncTransport.new(
        nil,
        100,
        trace_task,
        service_task,
        interval
      )
    end

    let(:interval) { 10 }

    context 'which underruns the timeout' do
      let(:trace_task) { spy('trace task') }
      let(:service_task) { spy('service task') }

      it do
        expect(trace_task).to have_received(:call).once
        expect(service_task).to have_received(:call).once
        expect(@shutdown_end - @shutdown_beg).to be < Datadog::Workers::AsyncTransport::SHUTDOWN_TIMEOUT
      end
    end

    context 'which overruns the timeout' do
      let(:task) { proc { sleep(interval) } }
      let(:trace_task) { task }
      let(:service_task) { task }

      it do
        expect(@shutdown_end - @shutdown_beg).to be_within(0.5).of(Datadog::Workers::AsyncTransport::SHUTDOWN_TIMEOUT)
      end
    end
  end
end
