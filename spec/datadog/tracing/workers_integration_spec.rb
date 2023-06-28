require 'spec_helper'

require 'time'
require 'json'

require 'datadog/tracing'
require 'datadog/tracing/pipeline'
require 'datadog/tracing/pipeline/span_filter'
require 'datadog/tracing/trace_segment'
require 'datadog/tracing/workers'
require 'datadog/tracing/writer'

RSpec.describe 'Datadog::Workers::AsyncTransport integration tests' do
  let(:hostname) { 'http://127.0.0.1' }
  let(:writer) do
    Datadog::Tracing::Writer.new.tap do |w|
      # write some stuff to trigger a #start
      w.write(Datadog::Tracing::TraceSegment.new([]))

      # now stop the writer and replace worker with ours, if we don't do
      # this the old worker will still be used.
      w.stop
      w.instance_variable_set(
        :@worker,
        Datadog::Tracing::Workers::AsyncTransport.new(
          transport: transport,
          buffer_size: buffer_size,
          on_trace: w.instance_variable_get(:@trace_handler),
          interval: flush_interval
        )
      )
      w.worker.start
    end
  end
  # Use SpyTransport instead of shared context because
  # worker threads sometimes call test objects after test finishes.
  let(:transport) { SpyTransport.new }
  let(:stats) { writer.stats }
  let(:dump) { transport.dump }
  let(:port) { 1234 }
  let(:flush_interval) { 0.1 }
  let(:buffer_size) { 10 }

  let(:tracer) { Datadog::Tracing.send(:tracer) }

  before do
    Datadog.configure do |c|
      c.tracing.writer = writer
    end
  end

  after { tracer.shutdown! }

  def wait_for_flush(num = 1, period = 0.1)
    (20 * flush_interval).to_i.times do
      break if block_given? ? yield : writer.stats[:traces_flushed] >= num

      sleep(period)
    end
  end

  describe 'when sending spans' do
    let(:dumped_traces) { dump[200][:traces] }
    let(:trace_payload) { JSON.parse(dumped_traces[0]) }
    let(:trace) { trace_payload[0] }
    let(:dumped_span) { trace[0] }

    # Test that one single span, in the most simple case, is correctly handled.
    # this is not purely an integration test as it does not rely on a real agent
    # but it checks that all the machinery around workers (tracer/writer/worker/transport)
    # is consistent and that data flows through it.
    context 'with service names' do
      before do
        skip 'TODO: Test is flaky on macOS' if RUBY_PLATFORM.include?('darwin')

        tracer.trace('my.op', service: 'my.service') do
          sleep(0.001)
        end

        wait_for_flush
      end

      it 'flushes the trace correctly' do
        expect(stats[:traces_flushed]).to be >= 1
        expect(stats[:services_flushed]).to be_nil

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
      before do
        skip 'TODO: Test is flaky on macOS' if RUBY_PLATFORM.include?('darwin')

        tracer.trace('my.op') do
          sleep(0.001)
        end

        wait_for_flush
      end

      it 'flushes the trace correctly' do
        expect(stats[:traces_flushed]).to be >= 1

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
      before do
        skip 'TODO: Test is flaky on macOS' if RUBY_PLATFORM.include?('darwin')

        # Activate filter
        filter = Datadog::Tracing::Pipeline::SpanFilter.new do |span|
          span.name[/discard/]
        end

        Datadog::Tracing::Pipeline.before_flush(filter)

        # Create spans
        tracer.trace('keep', service: 'tracer-test').finish
        tracer.trace('discard', service: 'tracer-test').finish

        wait_for_flush(2)
      end

      after { Datadog::Tracing::Pipeline.processors = [] }

      it 'filters the trace correctly' do
        expect(transport.helper_sent[200][:traces].to_s).to match(/keep/)
        expect(transport.helper_sent[200][:traces].to_s).to_not match(/discard/)
      end
    end
  end

  describe 'when setting service info' do
    let(:dumped_services) { dump[200][:services] }

    # Test that services are correctly flushed, with two of them
    context 'for two services' do
      before do
        tracer.trace('my.op').finish
      end

      it 'flushes the services correctly' do
        expect(stats[:services_flushed]).to be_nil

        # Sanity checks
        expect(dump[200]).to_not be nil
        expect(dump[500]).to_not be nil
        expect(dump[500]).to eq({})

        # No services information was sent
        expect(dumped_services).to be_nil
      end
    end
  end

  describe 'when terminating the worker' do
    before do
      worker.start

      # Let it reach the 10 seconds back-off
      sleep(0.5)

      # Enqueue some work for a final flush
      worker.enqueue_trace(get_test_traces(1))

      # Interrupt back off and flush everything immediately
      @shutdown_beg = Time.now
      worker.stop
      @shutdown_end = Time.now
    end

    let(:worker) do
      Datadog::Tracing::Workers::AsyncTransport.new(
        transport: nil,
        buffer_size: 100,
        on_trace: trace_task,
        on_service: service_task,
        interval: interval
      )
    end
    let(:interval) { 10 }

    after do
      thread = worker.instance_variable_get(:@worker)
      if thread
        thread.terminate
        thread.join
      end
    end

    context 'which underruns the timeout' do
      let(:trace_task) { spy('trace task') }
      let(:service_task) { spy('service task') }

      it do
        expect(trace_task).to have_received(:call).once
        expect(service_task).to_not have_received(:call)
        expect(@shutdown_end - @shutdown_beg)
          .to be < Datadog::Tracing::Workers::AsyncTransport::SHUTDOWN_TIMEOUT
      end
    end

    context 'which overruns the timeout' do
      let(:task) { proc { sleep(10) } }
      let(:trace_task) { task }
      let(:service_task) { task }

      it 'interrupts the worker to speed up shutdown' do
        expect(@shutdown_end - @shutdown_beg)
          .to be_within(5).of(
            Datadog::Tracing::Workers::AsyncTransport::SHUTDOWN_TIMEOUT
          )
      end
    end
  end
end
