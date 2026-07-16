# frozen_string_literal: true

require 'datadog/tracing/transport/native'
require 'datadog/tracing/writer'
require 'datadog/tracing/span'
require 'datadog/tracing/trace_segment'
require 'datadog/tracing/transport/trace_formatter'
require 'datadog/core/utils/at_fork_monkey_patch'
require 'socket'
require 'json'

RSpec.describe Datadog::Tracing::Transport::Native::Transport do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:native_module) { Datadog::Tracing::Transport::Native }
  let(:transport_class) { native_module::Transport }

  # ---------------------------------------------------------------------------
  # Mock agent
  # ---------------------------------------------------------------------------

  class NativeTransportMockAgent # rubocop:disable Lint/ConstantDefinitionInBlock
    attr_reader :port

    def initialize(status: 200, body: '{"rate_by_service":{"service:,env:":1.0}}')
      @status = status
      @body = body
      @server = TCPServer.new('127.0.0.1', 0)
      @port = @server.addr[1]
      @thread = Thread.new { run }
    end

    def stop
      @running = false
      begin
        @server.close
      rescue
        nil
      end
      @thread.join(2)
    end

    private

    def run
      @running = true
      while @running
        client = begin
          @server.accept
        rescue
          break
        end
        handle(client)
      end
    end

    def handle(client)
      request_line = client.gets
      return client.close if request_line.nil?

      headers = {}
      while (line = client.gets) && line != "\r\n"
        key, value = line.split(': ', 2)
        headers[key.downcase] = value&.strip
      end

      body_len = (headers['content-length'] || 0).to_i
      client.read(body_len) if body_len > 0

      client.print "HTTP/1.1 #{@status} OK\r\n"
      client.print "Content-Length: #{@body.bytesize}\r\n"
      client.print "Content-Type: application/json\r\n"
      client.print "\r\n"
      client.print @body
      client.close
    rescue => e
      warn "MockAgent error: #{e}" if ENV['DEBUG']
      client&.close
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  let(:mock_agent) { NativeTransportMockAgent.new }
  after { mock_agent.stop }

  let(:agent_settings) do
    double('agent_settings', url: "http://127.0.0.1:#{mock_agent.port}")
  end

  # Track every transport built by these examples so we can deterministically
  # dispose of it afterwards, freeing its native exporter during the run rather
  # than at interpreter exit (see NativeTransportForkIsolation.dispose).
  let(:built_transports) { [] }

  let(:transport) do
    transport_class.new(agent_settings: agent_settings, logger: logger).tap do |t|
      built_transports << t
    end
  end

  after { built_transports.each { |t| NativeTransportForkIsolation.dispose(t) } }

  let(:logger) { Logger.new(File::NULL) }

  def make_trace_segment(*span_names)
    trace_id = rand(1 << 62)
    spans = span_names.map do |name|
      Datadog::Tracing::Span.new(
        name,
        service: 'test-svc',
        resource: 'GET /test',
        id: rand(1 << 62),
        parent_id: 0,
        trace_id: trace_id,
      )
    end
    Datadog::Tracing::TraceSegment.new(spans, id: trace_id, root_span_id: spans.first.id)
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe '.supported?' do
    it 'returns true when native extension is loaded' do
      expect(native_module.supported?).to be true
    end
  end

  describe '#initialize' do
    it 'creates a transport' do
      expect(transport).to be_a(transport_class)
    end

    it 'raises when native extension is not available' do
      allow(native_module).to receive(:supported?).and_return(false)
      stub_const("#{native_module}::UNSUPPORTED_REASON", 'test failure')

      expect {
        transport_class.new(agent_settings: agent_settings)
      }.to raise_error(RuntimeError, /not supported/)
    end
  end

  describe 'fork-hook lifecycle' do
    let(:at_fork) { Datadog::Core::Utils::AtForkMonkeyPatch }

    def registry(stage)
      const = {before: :AT_FORK_BEFORE_BLOCKS, parent: :AT_FORK_PARENT_BLOCKS, child: :AT_FORK_CHILD_BLOCKS}.fetch(stage)
      at_fork.const_get(const)
    end

    # Identity membership check. We must NOT use RSpec's `include(block)` here:
    # `include` treats a Proc argument as a case-equality predicate and *calls*
    # it against each element, which would both invoke the native fork hook and
    # report false matches.
    def registry_contains?(stage, block)
      registry(stage).any? { |b| b.equal?(block) }
    end

    describe '#initialize' do
      it 'registers one before/parent/child hook' do
        hooks = transport.instance_variable_get(:@fork_hooks)

        expect(hooks.keys).to contain_exactly(:before, :parent, :child)
        hooks.each do |stage, block|
          expect(registry_contains?(stage, block)).to be(true)
        end
      end
    end

    describe '#close' do
      it 'removes all of its hooks from the global registry' do
        hooks = transport.instance_variable_get(:@fork_hooks)

        transport.close

        hooks.each do |stage, block|
          expect(registry_contains?(stage, block)).to be(false)
        end
      end

      it 'clears the exporter so it can be freed' do
        transport.close
        expect(transport.instance_variable_get(:@exporter)).to be_nil
      end

      it 'stops the exporter native fork hooks from firing on a later fork' do
        exporter = transport.instance_variable_get(:@exporter)
        # If our hooks were still registered, running the blocks would invoke
        # these native methods.
        allow(exporter).to receive(:_native_before_fork)
        allow(exporter).to receive(:_native_after_fork_in_parent)
        allow(exporter).to receive(:_native_after_fork_in_child)

        transport.close

        at_fork.run_at_fork_blocks(:before)
        at_fork.run_at_fork_blocks(:parent)
        at_fork.run_at_fork_blocks(:child)

        expect(exporter).to_not have_received(:_native_before_fork)
        expect(exporter).to_not have_received(:_native_after_fork_in_parent)
        expect(exporter).to_not have_received(:_native_after_fork_in_child)
      end

      it 'is idempotent' do
        transport.close
        expect { transport.close }.to_not raise_error
      end

      it 'causes subsequent sends to return an internal error response' do
        transport.close

        responses = transport.send_traces([make_trace_segment('web.request')])

        expect(responses).to contain_exactly(
          an_instance_of(Datadog::Tracing::Transport::Native::InternalErrorResponse)
        )
      end
    end

    describe 'finalizer fallback' do
      it 'registers a finalizer on the transport at construction' do
        # The finalizer guards against a transport that is dropped without
        # #close: it must still deregister the global fork hooks.
        expect(ObjectSpace).to receive(:define_finalizer).with(kind_of(transport_class), kind_of(Proc))
        transport
      end

      it 'builds a finalizer in class scope so it cannot capture a transport instance' do
        # A finalizer that closed over the Transport it is attached to would
        # keep that object reachable, so it would never fire. Building it in a
        # class method guarantees its binding receiver is the class, not an
        # instance.
        hooks = transport.instance_variable_get(:@fork_hooks)
        finalizer = transport_class.send(:finalizer_for, hooks)

        expect(finalizer.binding.receiver).to be(transport_class)
        expect(finalizer.binding.receiver).to_not be(transport)
      end

      it 'removes all the hooks when the finalizer runs' do
        hooks = transport.instance_variable_get(:@fork_hooks)
        finalizer = transport_class.send(:finalizer_for, hooks)

        # Simulate finalization (what ObjectSpace would call once the transport
        # is collected). The finalizer receives the object id; ignore it.
        finalizer.call(transport.object_id)

        hooks.each do |stage, block|
          expect(registry_contains?(stage, block)).to be(false)
        end
      end
    end

    describe 'teardown via Writer#stop' do
      # The native transport is plugged into a Writer via its :transport option.
      # Stopping a Writer is a permanent teardown, so it must deterministically
      # #close the native transport, deregistering its global fork hooks rather
      # than leaving them to the GC finalizer.
      it 'closes the native transport and removes its fork hooks on writer stop' do
        hooks = transport.instance_variable_get(:@fork_hooks)

        writer = Datadog::Tracing::Writer.new(
          transport: transport,
          agent_settings: agent_settings,
          logger: logger,
        )

        writer.stop

        hooks.each do |stage, block|
          expect(registry_contains?(stage, block)).to be(false)
        end
        expect(transport.instance_variable_get(:@exporter)).to be_nil
      end
    end
  end

  describe '#send_traces' do
    context 'with an empty array' do
      it 'returns an empty array' do
        expect(transport.send_traces([])).to eq([])
      end
    end

    context 'with a single trace' do
      it 'returns a success response' do
        trace = make_trace_segment('web.request')
        responses = transport.send_traces([trace])

        expect(responses).to be_an(Array)
        expect(responses.length).to eq(1)
        expect(responses.first.ok?).to be true
      end

      it 'updates stats on success' do
        trace = make_trace_segment('web.request')
        transport.send_traces([trace])

        expect(transport.stats.success).to eq(1)
        expect(transport.stats.internal_error).to eq(0)
      end
    end

    context 'with multiple traces' do
      it 'returns a success response' do
        traces = [
          make_trace_segment('op1', 'op2'),
          make_trace_segment('op3'),
        ]
        responses = transport.send_traces(traces)

        expect(responses.first.ok?).to be true
        expect(responses.first.trace_count).to eq(2)
      end
    end

    context 'when an exception occurs' do
      it 'returns an InternalErrorResponse' do
        allow_any_instance_of(transport_class)
          .to receive(:tracer_version_string).and_return('1.0')

        # Force an error by passing something that will fail conversion
        bad_traces = [double('bad_trace', spans: nil)]
        allow(Datadog::Tracing::Transport::TraceFormatter).to receive(:format!)

        responses = transport.send_traces(bad_traces)

        expect(responses.length).to eq(1)
        expect(responses.first).to be_a(native_module::InternalErrorResponse)
        expect(responses.first.ok?).to be false
        expect(responses.first.internal_error?).to be true
      end

      it 'updates stats on exception' do
        bad_traces = [double('bad_trace', spans: nil)]
        allow(Datadog::Tracing::Transport::TraceFormatter).to receive(:format!)

        transport.send_traces(bad_traces)

        expect(transport.stats.internal_error).to eq(1)
        expect(transport.stats.consecutive_errors).to eq(1)
      end
    end
  end

  describe '#stats' do
    it 'returns a Statistics::Counts object' do
      counts = transport.stats
      expect(counts).to respond_to(:success, :client_error, :server_error, :internal_error, :consecutive_errors, :reset!)
    end

    it 'starts with zero counts' do
      counts = transport.stats
      expect(counts.success).to eq(0)
      expect(counts.client_error).to eq(0)
      expect(counts.server_error).to eq(0)
      expect(counts.internal_error).to eq(0)
      expect(counts.consecutive_errors).to eq(0)
    end
  end
end

RSpec.describe Datadog::Tracing::Transport::Native::InternalErrorResponse do
  let(:error) { RuntimeError.new('test error') }
  subject(:response) { described_class.new(error) }

  it { expect(response.ok?).to be false }
  it { expect(response.internal_error?).to be true }
  it { expect(response.server_error?).to be false }
  it { expect(response.client_error?).to be false }
  it { expect(response.not_found?).to be false }
  it { expect(response.unsupported?).to be false }
  it { expect(response.payload).to be_nil }
  it { expect(response.trace_count).to eq(0) }
  it { expect(response.error).to eq(error) }
  it { expect(response.inspect).to include('RuntimeError') }
end
