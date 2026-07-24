# frozen_string_literal: true

require "datadog/tracing/transport/native"
require "datadog/tracing/span"
require "datadog/tracing/trace_segment"
require "datadog/core/utils/at_fork_monkey_patch"
require "socket"
require "timeout"

# Integration tests for the native trace exporter's fork-safety and
# cooperative cancellation behaviour.
#
# The native transport speaks HTTP from Rust and bypasses WebMock, so these
# tests stand up real local TCP mock agents (forked processes, to avoid
# leaking Ruby acceptor threads into the parent) and exercise the full path:
#
#   Ruby Span -> C extension -> Rust pipeline -> HTTP -> mock agent
#
RSpec.describe "Native transport fork safety and cancellation" do
  before { skip_if_libdatadog_not_supported }

  before(:all) do
    skip "Fork not supported on this platform" unless ::Process.respond_to?(:fork)
  end

  # ---------------------------------------------------------------------------
  # Mock agents (run in forked processes; no Ruby threads leak into the parent)
  # ---------------------------------------------------------------------------

  # Accepts connections and answers every request with `200 OK` plus a small
  # JSON body shaped like the agent's `rate_by_service` response.
  class RespondingMockAgent # rubocop:disable Lint/ConstantDefinitionInBlock
    attr_reader :port

    def initialize
      server = TCPServer.new("127.0.0.1", 0)
      @port = server.addr[1]

      @pid = fork do
        body = '{"rate_by_service":{"service:,env:":1.0}}'
        response = "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n" \
                   "Content-Type: application/json\r\n\r\n#{body}"

        loop do
          client = begin
            server.accept
          rescue
            break
          end
          Thread.new(client) do |c|
            request_line = c.gets
            next c.close if request_line.nil?

            content_length = 0
            while (line = c.gets) && line != "\r\n"
              content_length = line.split(": ", 2).last.to_i if line.downcase.start_with?("content-length")
            end
            c.read(content_length) if content_length > 0

            c.print response
          rescue # rubocop:disable Lint/SuppressedException
          ensure
            begin
              c.close
            rescue
              nil
            end
          end
        end
      end

      server.close
    end

    def stop
      NativeTransportForkIsolation.reap_process(@pid)
    end
  end

  # Accepts connections and holds them open WITHOUT ever responding, so any
  # in-flight send blocks waiting for the HTTP response. Each accepted
  # connection writes one byte to a pipe so the parent can observe that a
  # send actually reached the agent (is in-flight) before interrupting it.
  class SilentMockAgent # rubocop:disable Lint/ConstantDefinitionInBlock
    attr_reader :port

    def initialize
      @read_io, @write_io = IO.pipe
      server = TCPServer.new("127.0.0.1", 0)
      @port = server.addr[1]

      @pid = fork do
        @read_io.close
        held = [] # keep accepted sockets open (never respond)
        loop do
          client = begin
            server.accept
          rescue
            break
          end
          held << client
          begin
            @write_io.write("x")
          rescue
            nil
          end
        end
      end

      server.close
      @write_io.close
    end

    # Block until the agent has accepted at least one connection.
    def wait_for_connection(timeout: 5)
      ready = IO.select([@read_io], nil, nil, timeout)
      raise "Timed out waiting for the native send to reach the mock agent" unless ready

      @read_io.read(1)
    end

    def stop
      NativeTransportForkIsolation.reap_process(@pid)
      begin
        @read_io.close
      rescue
        nil
      end
    end
  end

  # Accepts connections, signals (via a pipe) that a request has arrived and is
  # in-flight, waits a fixed delay, then answers with `200 OK`. The delay lets a
  # test fork WHILE a send is mid-flight (the agent has received the request but
  # not yet replied), so the fork's `:before` hook must wait for the in-flight
  # send to drain before tearing down the runtime.
  class DelayingMockAgent # rubocop:disable Lint/ConstantDefinitionInBlock
    attr_reader :port

    def initialize(delay:)
      @read_io, @write_io = IO.pipe
      server = TCPServer.new("127.0.0.1", 0)
      @port = server.addr[1]

      @pid = fork do
        @read_io.close
        body = '{"rate_by_service":{"service:,env:":1.0}}'
        response = "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n" \
                   "Content-Type: application/json\r\n\r\n#{body}"

        loop do
          client = begin
            server.accept
          rescue
            break
          end
          Thread.new(client) do |c|
            request_line = c.gets
            next c.close if request_line.nil?

            content_length = 0
            while (line = c.gets) && line != "\r\n"
              content_length = line.split(": ", 2).last.to_i if line.downcase.start_with?("content-length")
            end
            c.read(content_length) if content_length > 0

            # Signal that the request has arrived and is in-flight, THEN delay
            # before replying so the send stays in-flight for `delay` seconds.
            begin
              @write_io.write("x")
            rescue
              nil
            end
            sleep delay

            c.print response
          rescue # rubocop:disable Lint/SuppressedException
          ensure
            begin
              c.close
            rescue
              nil
            end
          end
        end
      end

      server.close
      @write_io.close
    end

    # Block until the agent has received at least one request (send in-flight).
    def wait_for_connection(timeout: 5)
      ready = IO.select([@read_io], nil, nil, timeout)
      raise "Timed out waiting for the native send to reach the mock agent" unless ready

      @read_io.read(1)
    end

    def stop
      NativeTransportForkIsolation.reap_process(@pid)
      begin
        @read_io.close
      rescue
        nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  # Save/restore the global AtForkMonkeyPatch registries.
  module AtForkRegistryHelpers # rubocop:disable Lint/ConstantDefinitionInBlock
    module_function

    STAGES = {
      before: :AT_FORK_BEFORE_BLOCKS,
      parent: :AT_FORK_PARENT_BLOCKS,
      child: :AT_FORK_CHILD_BLOCKS,
    }.freeze

    def snapshot_and_clear
      STAGES.each_with_object({}) do |(stage, const), saved|
        array = Datadog::Core::Utils::AtForkMonkeyPatch.const_get(const)
        saved[stage] = array.dup
        array.clear
      end
    end

    def restore(saved)
      STAGES.each do |stage, const|
        Datadog::Core::Utils::AtForkMonkeyPatch.const_get(const).replace(saved[stage])
      end
    end
  end

  def build_trace(name: "fork.op")
    trace_id = rand(1 << 62)
    span = Datadog::Tracing::Span.new(
      name,
      service: "fork-svc",
      resource: name,
      type: "web",
      id: rand(1 << 62),
      parent_id: 0,
      trace_id: trace_id,
    )
    Datadog::Tracing::TraceSegment.new([span], id: trace_id, root_span_id: span.id)
  end

  def run_with_transport(example, fork_hooks: false, stop_agent_first: false)
    saved_at_fork = AtForkRegistryHelpers.snapshot_and_clear
    Datadog::Core::Utils::AtForkMonkeyPatch.apply! if fork_hooks

    @mock_agent = yield
    agent_settings = Struct.new(:url).new("http://127.0.0.1:#{@mock_agent.port}")
    @transport = Datadog::Tracing::Transport::Native::Transport.new(
      agent_settings: agent_settings,
      logger: Logger.new(File::NULL),
    )

    example.run
  ensure
    begin
      @mock_agent&.stop if stop_agent_first
    ensure
      begin
        NativeTransportForkIsolation.dispose(@transport)
      ensure
        begin
          AtForkRegistryHelpers.restore(saved_at_fork)
        ensure
          @transport = nil
          begin
            GC.start
          ensure
            begin
              @mock_agent&.stop unless stop_agent_first
            ensure
              @mock_agent = nil
            end
          end
        end
      end
    end
  end

  # ===========================================================================
  # 1. Fork lifecycle
  # ===========================================================================
  describe "fork lifecycle" do
    around do |example|
      run_with_transport(example, fork_hooks: true) { RespondingMockAgent.new }
    end

    let(:transport) { @transport }
    let(:exporter) { transport.instance_variable_get(:@exporter) }

    it "sends successfully from both the parent and a forked child, and fires the parent-side hooks" do
      # Spy on the lifecycle hooks but keep their real behaviour, so we can
      # assert the registered :before/:parent stages fired in the parent
      # around the fork without breaking the runtime.
      allow(exporter).to receive(:_native_before_fork).and_call_original
      allow(exporter).to receive(:_native_after_fork_in_parent).and_call_original

      # Parent works before forking.
      expect(transport.send_traces([build_trace]).first.ok?).to be(true)

      read_io, write_io = IO.pipe
      pid = fork do
        read_io.close
        # The :child hook (_native_after_fork_in_child) has already run inside
        # `_fork`, rebuilding the runtime that the inherited copy left dead.
        result =
          begin
            response = transport.send_traces([build_trace(name: "child.op")]).first
            response.ok? ? "OK" : "NOT_OK:#{response.inspect}"
          rescue => e
            "RAISED:#{e.class}:#{e.message}"
          end
        write_io.write(result)
        write_io.close
        exit!(0)
      end
      write_io.close

      child_result =
        begin
          Timeout.timeout(15) { read_io.read }
        ensure
          read_io.close
        end
      _, status = Process.wait2(pid)

      expect(child_result).to eq("OK")
      expect(status.success?).to be(true)

      # The parent-side stages fired around the fork.
      expect(exporter).to have_received(:_native_before_fork).at_least(:once)
      expect(exporter).to have_received(:_native_after_fork_in_parent).at_least(:once)

      # Parent still works after the fork.
      expect(transport.send_traces([build_trace]).first.ok?).to be(true)
    end
  end

  # ===========================================================================
  # 2. Cooperative cancellation / interrupt propagation
  # ===========================================================================
  describe "cooperative cancellation" do
    around do |example|
      run_with_transport(example, stop_agent_first: true) { SilentMockAgent.new }
    end

    let(:transport) { @transport }
    let(:mock_agent) { @mock_agent }

    it "returns promptly when the sending thread is killed mid-flight, without masking the interrupt" do
      # A queue that only receives a value if `send_traces` *returns* (either a
      # success or an error response). If the kill is masked by an ordinary
      # response, this queue ends up non-empty.
      returned = Queue.new

      sender = Thread.new do
        Thread.current.report_on_exception = false
        response = transport.send_traces([build_trace(name: "blocking.op")])
        # Only reached if the blocking send returned instead of being killed.
        returned.push(response)
      end

      # Wait until the send has actually reached the agent and is blocked
      # waiting for a response that never comes.
      mock_agent.wait_for_connection(timeout: 10)
      # Give the request a beat to settle into the blocking read.
      sleep 0.2

      kill_started = Datadog::Core::Utils::Time.get_time
      sender.kill

      # The cooperative cancellation token must abort the in-flight request so
      # the thread terminates promptly instead of hanging until a timeout.
      joined = sender.join(10)
      elapsed = Datadog::Core::Utils::Time.get_time - kill_started

      expect(joined).to_not be_nil, "sending thread did not terminate promptly after kill (it hung)"
      expect(sender.alive?).to be(false)
      expect(elapsed).to be < 5

      # The interrupt must propagate: the killed send must NOT have returned a
      # normal/error response that swallows the kill.
      expect(returned).to be_empty,
        "expected the killed send to propagate the interrupt, but it returned: #{returned.pop unless returned.empty?}"
    end
  end

  # ===========================================================================
  # 3. Fork while a send is in-flight
  # ===========================================================================
  #
  # A libdatadog Rust send must not be interrupted by `fork()`: the native send
  # releases the GVL, and `_native_before_fork` tears down/replaces the runtime,
  # so forking mid-send would leave the child with a half-completed send and
  # Rust-internal locks (deadlock/crash). The transport guards this with a
  # per-transport mutex held across the fork: the `:before` hook blocks until
  # any in-flight send drains before `_native_before_fork` runs.
  describe "fork while a send is in-flight" do
    # Keep the delay comfortably larger than the slack we allow when asserting
    # the fork blocked for the send to drain.
    AGENT_DELAY = 1.0 # rubocop:disable Lint/ConstantDefinitionInBlock

    around do |example|
      run_with_transport(example, fork_hooks: true) { DelayingMockAgent.new(delay: AGENT_DELAY) }
    end

    let(:transport) { @transport }
    let(:mock_agent) { @mock_agent }

    it "drains the in-flight send before the fork, and both child and parent send succeed" do
      # The background send's result, pushed only when send_traces returns.
      sender_result = Queue.new

      sender = Thread.new do
        Thread.current.report_on_exception = false
        sender_result.push(transport.send_traces([build_trace(name: "inflight.op")]))
      end

      # Wait until the send has actually reached the agent (is in-flight). The
      # agent then sleeps AGENT_DELAY before replying, so the send is still
      # holding @send_mutex when we fork below.
      mock_agent.wait_for_connection(timeout: 10)

      # Fork through the real AtForkMonkeyPatch path so the transport's
      # :before/:parent/:child hooks run. The :before hook locks @send_mutex,
      # which BLOCKS until the in-flight send finishes, so `fork` itself blocks
      # here for ~AGENT_DELAY.
      read_io, write_io = IO.pipe
      fork_started = Datadog::Core::Utils::Time.get_time
      pid = Timeout.timeout(15) do
        fork do
          read_io.close
          result =
            begin
              response = transport.send_traces([build_trace(name: "child.op")]).first
              response.ok? ? "OK" : "NOT_OK:#{response.inspect}"
            rescue => e
              "RAISED:#{e.class}:#{e.message}"
            end
          write_io.write(result)
          write_io.close
          exit!(0)
        end
      end
      fork_elapsed = Datadog::Core::Utils::Time.get_time - fork_started
      write_io.close

      child_result =
        begin
          Timeout.timeout(15) { read_io.read }
        ensure
          read_io.close
        end
      _, status = Process.wait2(pid)

      # The fork's :before hook must have waited for the in-flight send to
      # drain before tearing down the runtime. Because the agent holds the
      # request for AGENT_DELAY before replying, `fork` blocks for at least
      # that long (minus generous slack to stay non-flaky). The background send
      # must therefore have completed by the time the child ran.
      expect(fork_elapsed).to be >= (AGENT_DELAY * 0.5),
        "expected fork to block until the in-flight send drained (>= #{AGENT_DELAY * 0.5}s), " \
        "but it returned after #{fork_elapsed}s"
      expect(sender_result).to_not be_empty,
        "expected the in-flight send to have completed before the child started"

      # No deadlock/crash/SIGSEGV: the child sent successfully and exited 0.
      expect(child_result).to eq("OK")
      expect(status.success?).to be(true)

      # The in-flight parent send completed without error.
      parent_responses = sender_result.pop
      expect(parent_responses.first.ok?).to be(true)
      expect(sender.join(10)).to_not be_nil

      # The parent transport still works after the fork.
      expect(transport.send_traces([build_trace(name: "after.op")]).first.ok?).to be(true)
    end
  end
end
