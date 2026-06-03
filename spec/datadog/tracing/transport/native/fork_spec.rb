# frozen_string_literal: true

require 'datadog/tracing/transport/native'
require 'datadog/tracing/span'
require 'datadog/tracing/trace_segment'
require 'datadog/core/utils/at_fork_monkey_patch'
require 'socket'
require 'timeout'

# Integration tests for the native trace exporter's fork-safety and
# cooperative cancellation behaviour.
#
# The native transport speaks HTTP from Rust and bypasses WebMock, so these
# tests stand up real local TCP mock agents (forked processes, to avoid
# leaking Ruby acceptor threads into the parent) and exercise the full path:
#
#   Ruby Span -> C extension -> Rust pipeline -> HTTP -> mock agent
#
RSpec.describe 'Native transport fork safety and cancellation' do
  before { skip_if_libdatadog_not_supported }

  before(:all) do
    skip 'Fork not supported on this platform' unless ::Process.respond_to?(:fork)
  end

  # ---------------------------------------------------------------------------
  # Mock agents (run in forked processes; no Ruby threads leak into the parent)
  # ---------------------------------------------------------------------------

  # Forcefully terminate and reap a forked mock-agent process.
  #
  # Uses SIGKILL (which cannot be trapped/ignored, unlike SIGTERM which the
  # child may inherit a handler for from the RSpec process) and reaps with a
  # bounded, non-blocking poll so cleanup can never hang the suite.
  module ForkSpecHelpers
    module_function

    def reap_process(pid)
      return if pid.nil?

      Process.kill('KILL', pid) rescue nil
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      loop do
        reaped = (Process.wait(pid, Process::WNOHANG) rescue pid) # treat ECHILD as done
        break if reaped
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.02
      end
    end
  end

  # Accepts connections and answers every request with `200 OK` plus a small
  # JSON body shaped like the agent's `rate_by_service` response.
  class RespondingMockAgent
    attr_reader :port

    def initialize
      server = TCPServer.new('127.0.0.1', 0)
      @port = server.addr[1]

      @pid = fork do
        body = '{"rate_by_service":{"service:,env:":1.0}}'
        response = "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n" \
                   "Content-Type: application/json\r\n\r\n#{body}"

        loop do
          client = server.accept rescue break
          Thread.new(client) do |c|
            begin
              request_line = c.gets
              next c.close if request_line.nil?

              content_length = 0
              while (line = c.gets) && line != "\r\n"
                content_length = line.split(': ', 2).last.to_i if line.downcase.start_with?('content-length')
              end
              c.read(content_length) if content_length > 0

              c.print response
            rescue # rubocop:disable Lint/SuppressedException
            ensure
              c.close rescue nil
            end
          end
        end
      end

      server.close
    end

    def stop
      ForkSpecHelpers.reap_process(@pid)
    end
  end

  # Accepts connections and holds them open WITHOUT ever responding, so any
  # in-flight send blocks waiting for the HTTP response. Each accepted
  # connection writes one byte to a pipe so the parent can observe that a
  # send actually reached the agent (is in-flight) before interrupting it.
  class SilentMockAgent
    attr_reader :port

    def initialize
      @read_io, @write_io = IO.pipe
      server = TCPServer.new('127.0.0.1', 0)
      @port = server.addr[1]

      @pid = fork do
        @read_io.close
        held = [] # keep accepted sockets open (never respond)
        loop do
          client = server.accept rescue break
          held << client
          @write_io.write('x') rescue nil
        end
      end

      server.close
      @write_io.close
    end

    # Block until the agent has accepted at least one connection.
    def wait_for_connection(timeout: 5)
      ready = IO.select([@read_io], nil, nil, timeout)
      raise 'Timed out waiting for the native send to reach the mock agent' unless ready

      @read_io.read(1)
    end

    def stop
      ForkSpecHelpers.reap_process(@pid)
      @read_io.close rescue nil
    end
  end

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  # Save/restore the global AtForkMonkeyPatch registries. Defined as module
  # functions so they are callable from `before(:all)`/`after(:all)` hooks,
  # which run outside example scope.
  module AtForkRegistryHelpers
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

  def build_trace(name: 'fork.op')
    trace_id = rand(1 << 62)
    span = Datadog::Tracing::Span.new(
      name,
      service: 'fork-svc',
      resource: name,
      type: 'web',
      id: rand(1 << 62),
      parent_id: 0,
      trace_id: trace_id,
    )
    Datadog::Tracing::TraceSegment.new([span], id: trace_id, root_span_id: span.id)
  end

  # ===========================================================================
  # 1. Fork lifecycle
  # ===========================================================================
  describe 'fork lifecycle' do
    before(:all) do
      # Isolate the global AtForkMonkeyPatch registries so the only fork hooks
      # that fire during these tests are the ones registered by our transport.
      # Restored in after(:all).
      @saved_at_fork = AtForkRegistryHelpers.snapshot_and_clear

      # Enable the `_fork` / `fork` interception so that the transport's
      # before/parent/child hooks fire around a real fork.
      Datadog::Core::Utils::AtForkMonkeyPatch.apply!

      # Fork the mock agent *before* the transport registers its hooks: the
      # registries are empty at this point, so this fork is a hook no-op.
      @mock_agent = RespondingMockAgent.new

      agent_settings = Struct.new(:url).new("http://127.0.0.1:#{@mock_agent.port}")
      @transport = Datadog::Tracing::Transport::Native::Transport.new(
        agent_settings: agent_settings,
        logger: Logger.new('/dev/null'),
      )
    end

    after(:all) do
      # Drop the registered at-fork closures (which capture the exporter) FIRST,
      # so the exporter becomes collectable. Then free it via GC while the
      # responding agent is still alive, so its final flush succeeds quickly.
      # Only then stop the agent.
      AtForkRegistryHelpers.restore(@saved_at_fork)
      @transport = nil
      GC.start
      @mock_agent&.stop
    end

    let(:transport) { @transport }
    let(:exporter) { transport.instance_variable_get(:@exporter) }

    it 'sends successfully from both the parent and a forked child, and fires the parent-side hooks' do
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
            response = transport.send_traces([build_trace(name: 'child.op')]).first
            response.ok? ? 'OK' : "NOT_OK:#{response.inspect}"
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

      expect(child_result).to eq('OK')
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
  describe 'cooperative cancellation' do
    before(:all) do
      # The transport registers fork hooks on creation; keep them out of the
      # global registries so they cannot fire on unrelated forks elsewhere.
      @saved_at_fork = AtForkRegistryHelpers.snapshot_and_clear

      @mock_agent = SilentMockAgent.new
      agent_settings = Struct.new(:url).new("http://127.0.0.1:#{@mock_agent.port}")
      @transport = Datadog::Tracing::Transport::Native::Transport.new(
        agent_settings: agent_settings,
        logger: Logger.new('/dev/null'),
      )
    end

    after(:all) do
      # Stop the silent agent FIRST: it holds connections open and never
      # responds, so freeing the exporter while those connections are live
      # could block on a flush. Killing the agent closes the sockets, so the
      # exporter's flush fails fast and shutdown completes. Drop the at-fork
      # closures (which capture the exporter) before the GC that frees it.
      @mock_agent&.stop
      AtForkRegistryHelpers.restore(@saved_at_fork)
      @transport = nil
      GC.start
    end

    let(:transport) { @transport }
    let(:mock_agent) { @mock_agent }

    it 'returns promptly when the sending thread is killed mid-flight, without masking the interrupt' do
      # A queue that only receives a value if `send_traces` *returns* (either a
      # success or an error response). If the kill is masked by an ordinary
      # response, this queue ends up non-empty.
      returned = Queue.new

      sender = Thread.new do
        Thread.current.report_on_exception = false
        response = transport.send_traces([build_trace(name: 'blocking.op')])
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

      expect(joined).to_not be_nil, 'sending thread did not terminate promptly after kill (it hung)'
      expect(sender.alive?).to be(false)
      expect(elapsed).to be < 5

      # The interrupt must propagate: the killed send must NOT have returned a
      # normal/error response that swallows the kill.
      expect(returned).to be_empty,
        "expected the killed send to propagate the interrupt, but it returned: #{returned.pop unless returned.empty?}"
    end
  end
end
