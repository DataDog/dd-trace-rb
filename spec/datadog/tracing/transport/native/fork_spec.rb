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

  # Holds the first trace request until the parent explicitly releases it. This
  # gives the tests a deterministic in-flight send without timing sleeps.
  class BlockingMockAgent # rubocop:disable Lint/ConstantDefinitionInBlock
    attr_reader :port

    def initialize
      @request_read, @request_write = IO.pipe
      @release_read, @release_write = IO.pipe
      server = TCPServer.new("127.0.0.1", 0)
      @port = server.addr[1]

      @pid = fork do
        @request_read.close
        @release_write.close
        body = '{"rate_by_service":{"service:,env:":1.0}}'
        response = "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n" \
                   "Content-Type: application/json\r\n\r\n#{body}"
        blocked_trace = false

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

            if !blocked_trace && request_line.include?("/v0.")
              blocked_trace = true
              @request_write.write("x")
              @release_read.read(1)
            end

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
      @request_write.close
      @release_read.close
    end

    # Block until the agent has received at least one request (send in-flight).
    def wait_for_connection(timeout: 5)
      ready = IO.select([@request_read], nil, nil, timeout)
      raise "Timed out waiting for the native send to reach the mock agent" unless ready

      @request_read.read(1)
    end

    def release
      @release_write.write("x")
    end

    def stop
      NativeTransportForkIsolation.reap_process(@pid)
      @request_read.close unless @request_read.closed?
      @release_write.close unless @release_write.closed?
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

    it "restores the parent and unlocks sends when fork fails" do
      hooks = transport.instance_variable_get(:@fork_hooks)
      saved_at_fork = AtForkRegistryHelpers.snapshot_and_clear
      hooks.each do |stage, block|
        Datadog::Core::Utils::AtForkMonkeyPatch.at_fork(stage, &block)
      end

      allow(exporter).to receive(:_native_before_fork).and_call_original
      allow(exporter).to receive(:_native_after_fork_in_parent).and_call_original
      allow(exporter).to receive(:_native_after_fork_in_child).and_call_original

      failing_process = Module.new do
        define_singleton_method(:_fork) { raise Errno::EAGAIN }
      end
      failing_process.singleton_class.prepend(
        Datadog::Core::Utils::AtForkMonkeyPatch::ProcessMonkeyPatch
      )

      expect { failing_process._fork }.to raise_error(Errno::EAGAIN)
      expect(exporter).to have_received(:_native_before_fork).once
      expect(exporter).to have_received(:_native_after_fork_in_parent).once
      expect(exporter).to_not have_received(:_native_after_fork_in_child)
      expect(transport.send_traces([build_trace(name: "after-failed-fork.op")]).first.ok?).to be(true)
    ensure
      AtForkRegistryHelpers.restore(saved_at_fork) if saved_at_fork
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
  # per-transport mutex held across the fork: the `:before` hook pauses the
  # shared runtime, then blocks until any in-flight send drains.
  describe "fork while a send is in-flight" do
    around do |example|
      run_with_transport(example, fork_hooks: true) { BlockingMockAgent.new }
    end

    let(:transport) { @transport }
    let(:mock_agent) { @mock_agent }

    it "drains the in-flight send before the fork, and both child and parent send succeed" do
      exporter = transport.instance_variable_get(:@exporter)
      fork_prepared = Queue.new

      allow(exporter).to receive(:_native_before_fork).and_wrap_original do |method|
        result = method.call
        fork_prepared << true
        result
      end

      # The background send's result, pushed only when send_traces returns.
      sender_result = Queue.new

      sender = Thread.new do
        Thread.current.report_on_exception = false
        sender_result.push(transport.send_traces([build_trace(name: "inflight.op")]))
      end

      # Wait until the send has actually reached the agent (is in-flight). The
      # agent does not reply until explicitly released below.
      mock_agent.wait_for_connection(timeout: 10)

      # Fork through the real AtForkMonkeyPatch path so the transport's
      # :before/:parent/:child hooks run. The :before hook locks @send_mutex,
      # which BLOCKS until the in-flight send finishes, so `fork` itself blocks
      # until the releaser below allows the agent to answer.
      releaser = Thread.new do
        fork_prepared.pop
        mock_agent.release
      end
      read_io, write_io = IO.pipe
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
      write_io.close
      expect(releaser.join(5)).to be(releaser)

      child_result =
        begin
          Timeout.timeout(15) { read_io.read }
        ensure
          read_io.close
        end
      _, status = Process.wait2(pid)

      # The fork call cannot return until the agent releases the in-flight send,
      # so the background send must have completed before the child runs.
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
    ensure
      begin
        mock_agent.release
      rescue IOError, Errno::EPIPE
        nil
      end
      releaser&.join(5)
    end

    it "serializes close with an in-flight send and fork in both processes" do
      sender_result = Queue.new
      fork_result = Queue.new
      close_started = Queue.new

      sender = Thread.new do
        sender_result << transport.send_traces([build_trace(name: "inflight-close.op")])
      end
      mock_agent.wait_for_connection(timeout: 10)

      # Close acquires the lifecycle mutex, then blocks on the in-flight send.
      closer = Thread.new do
        close_started << true
        transport.close
      end
      close_started.pop
      Timeout.timeout(5) do
        Thread.pass until closer.status == "sleep" || !closer.alive?
      end
      expect(closer).to be_alive

      # Start the fork only after close is waiting for the send. Its before hook
      # announces itself before waiting for the lifecycle mutex, forcing close
      # to yield rather than removing the matching parent/child hooks.
      read_io, write_io = IO.pipe
      forker = Thread.new do
        pid = fork do
          read_io.close
          response = transport.send_traces([build_trace(name: "child-after-close-race.op")]).first
          write_io.write(response.ok? ? "OK" : "NOT_OK:#{response.inspect}")
          write_io.close
          exit!(0)
        end
        fork_result << pid
      end

      Timeout.timeout(5) do
        fork_state = transport.instance_variable_get(:@fork_state)
        Thread.pass until fork_state[:pending] > 0
      end

      mock_agent.release
      expect(sender.join(10)).to be(sender)
      expect(forker.join(10)).to be(forker)
      expect(closer.join(10)).to be(closer)
      write_io.close

      child_result = Timeout.timeout(15) { read_io.read }
      read_io.close
      _, status = Process.wait2(fork_result.pop)

      expect(sender_result.pop.first.ok?).to be(true)
      expect(child_result).to eq("OK")
      expect(status.success?).to be(true)
      expect(transport.send_traces([build_trace(name: "parent-after-close.op")]).first).to be_internal_error
    ensure
      begin
        mock_agent.release
      rescue IOError, Errno::EPIPE
        nil
      end
      sender&.join(5)
      forker&.join(5)
      closer&.join(5)
      read_io&.close unless read_io&.closed?
      write_io&.close unless write_io&.closed?
    end
  end
end
