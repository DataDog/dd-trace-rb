# frozen_string_literal: true

require "datadog/tracing/transport/native"
require "datadog/tracing/span"
require "datadog/tracing/trace_segment"
require "datadog/core/utils/at_fork_monkey_patch"
require "socket"
require "json"
require "timeout"
require "tmpdir"

RSpec.describe "Native exporter telemetry" do
  before do
    skip_if_libdatadog_not_supported
    skip "Requires fork-safe telemetry APIs" unless Datadog::Tracing::Transport::Native::TraceExporter._native_telemetry_supported?
    skip "Requires fork" unless Process.respond_to?(:fork)
    Datadog::Core::Utils::AtForkMonkeyPatch.apply!
  end

  class TelemetryAgent # rubocop:disable Lint/ConstantDefinitionInBlock
    attr_reader :port, :requests, :url

    def initialize(block_telemetry: false, block_trace: false, socket_path: nil)
      @socket_path = socket_path
      @read, write = IO.pipe
      release_read, @release = IO.pipe
      server = socket_path ? UNIXServer.new(socket_path) : TCPServer.new("127.0.0.1", 0)
      @port = server.addr[1] unless socket_path
      @url = socket_path ? "unix://#{socket_path}" : "http://127.0.0.1:#{port}"
      @requests = []
      @pid = fork do
        @read.close
        @release.close
        lock = Mutex.new
        trace_blocked = false
        loop do
          client = server.accept
          Thread.new(client) do |socket|
            line = socket.gets
            next unless line

            headers = {}
            while (header = socket.gets) && header != "\r\n"
              key, value = header.split(":", 2)
              headers[key.downcase] = value.strip
            end
            body = socket.read(headers.fetch("content-length", "0").to_i)
            request = {"path" => line.split[1], "headers" => headers, "body" => body.unpack1("H*")}
            block = lock.synchronize do
              write.puts(JSON.generate(request))
              if block_trace && !trace_blocked && request["path"].start_with?("/v0.")
                trace_blocked = true
              else
                block_telemetry && request["path"].include?("apmtelemetry")
              end
            end
            release_read.read(1) if block
            response = '{"rate_by_service":{}}'
            socket.write("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: #{response.bytesize}\r\n\r\n#{response}")
          rescue IOError, SystemCallError
            nil
          ensure
            socket.close
          end
        end
      end
      server.close
      write.close
      release_read.close
    end

    def request(path)
      Timeout.timeout(15) do
        loop do
          request = JSON.parse(@read.gets)
          @requests << request
          return request if path.match?(request.fetch("path"))
        end
      end
    end

    def telemetry
      request = request(/apmtelemetry/)
      request.merge("body" => JSON.parse([request.fetch("body")].pack("H*")))
    end

    def release
      @release.write("x")
    end

    def barrier
      socket = @socket_path ? UNIXSocket.new(@socket_path) : TCPSocket.new("127.0.0.1", port)
      socket.write("GET /barrier HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
      socket.read
    ensure
      socket&.close
    end

    def drain
      barrier
      read_until_barrier
    end

    def read_until_barrier
      Timeout.timeout(5) do
        loop do
          request = JSON.parse(@read.gets)
          return requests if request.fetch("path") == "/barrier"

          @requests << request
        end
      end
    end

    def stop
      NativeTransportForkIsolation.reap_process(@pid)
      @read.close
      @release.close
    end
  end

  let(:agent) { TelemetryAgent.new }
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |config|
      config.service = "native-telemetry-test"
      config.env = "test"
      config.version = "1.2.3"
      config.telemetry.enabled = true
      config.telemetry.metrics_enabled = true
      config.telemetry.heartbeat_interval_seconds = 3600
      config.telemetry.shutdown_timeout_seconds = 1
      config.telemetry.debug = true
    end
  end
  let(:transports) { [] }

  def build_transport(config = settings)
    Datadog::Tracing::Transport::Native::Transport.new(
      agent_settings: Struct.new(:url).new(agent.url),
      logger: Logger.new(File::NULL),
      settings: config,
    ).tap { |transport| transports << transport }
  end

  def send_trace(transport)
    span = Datadog::Tracing::Span.new("request", service: "native-telemetry-test", id: 123, trace_id: 456)
    trace = Datadog::Tracing::TraceSegment.new([span], id: 456, root_span_id: 123)
    expect(transport.send_traces([trace]).first).to be_ok
  end

  def identity
    id = Datadog::Core::Environment::Identity.id
    [id, Datadog::Core::Environment::Identity.root_runtime_id, Datadog::Core::Environment::Identity.parent_runtime_id]
  end

  def request_count(request)
    payloads = request.fetch("body").fetch("payload")
    series = payloads.flat_map { |payload| payload.fetch("payload").fetch("series", []) }
    series.select { |metric| metric["metric"] == "trace_api.requests" }.sum do |metric|
      expect(metric.fetch("tags")).to include("src_library:libdatadog")
      metric.fetch("points").sum { |_, value| value }
    end
  end

  after do
    transports.each(&:close)
    agent.stop
  end

  it "flushes successful sends with Ruby identity and no native lifecycle" do
    transport = build_transport
    parent = identity
    send_trace(transport)
    transport.close
    request = agent.telemetry
    expect(request.fetch("headers")).to include("dd-session-id" => parent.first, "dd-telemetry-debug-enabled" => "true")
    expect(request.fetch("body")).to include("runtime_id" => parent.first, "seq_id" => 1, "request_type" => "message-batch")
    expect(request.fetch("body").fetch("application")).to include(
      "service_name" => "native-telemetry-test", "env" => "test", "service_version" => "1.2.3",
      "language_name" => "ruby", "language_version" => RUBY_VERSION,
      "tracer_version" => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
    )
    expect(request.fetch("body").fetch("payload").map { |payload| payload.fetch("request_type") }).to all(match(/\A(generate-metrics|sketches)\z/))
    expect(request_count(request)).to eq(1)
    expect { transport.close }.not_to raise_error
  end

  it "isolates pending observations across children and grandchildren" do
    transport = build_transport
    parent = identity
    send_trace(transport)
    read, write = IO.pipe
    resume_read, resume_write = IO.pipe
    child = fork do
      read.close
      resume_write.close
      resume_read.read(1)
      resume_read.close
      child_identity = identity
      2.times { send_trace(transport) }
      grandchild = fork do
        write.puts(JSON.generate(identity))
        3.times { send_trace(transport) }
        transport.close
        exit! 0
      end
      Process.wait(grandchild)
      write.puts(JSON.generate(child_identity))
      transport.close
      write.close
      exit! 0
    end
    write.close
    resume_read.close
    send_trace(transport)
    transport.close
    resume_write.write("x")
    resume_write.close
    descendants = Timeout.timeout(15) { read.readlines.map { |line| JSON.parse(line) } }
    expect(Process.wait2(child).last).to be_success
    requests = Array.new(3) { agent.telemetry }
    grandchild, child_identity = descendants
    expect(child_identity).to eq([child_identity.first, parent[1] || parent.first, parent.first])
    expect(grandchild).to eq([grandchild.first, parent[1] || parent.first, child_identity.first])
    expect([parent.first, child_identity.first, grandchild.first].uniq.size).to eq(3)
    [[parent, 2], [child_identity, 2], [grandchild, 3]].each do |ids, count|
      request = requests.find { |item| item.fetch("body")["runtime_id"] == ids.first }
      expect(request_count(request)).to eq(count)
      expect(request.fetch("headers")["dd-session-id"]).to eq(ids.first)
      expect(request.fetch("headers")["dd-root-session-id"]).to eq(ids[1])
      expect(request.fetch("headers")["dd-parent-session-id"]).to eq(ids[2])
    end
  ensure
    read&.close
    write&.close unless write&.closed?
    resume_read&.close unless resume_read&.closed?
    resume_write&.close unless resume_write&.closed?
    NativeTransportForkIsolation.reap_process(child) if child.is_a?(Integer)
  end

  it "preserves buffered data and identity after a failed fork" do
    transport = build_transport
    parent = identity
    send_trace(transport)
    process = Module.new do
      def self._fork
        raise Errno::EAGAIN
      end
    end
    process.singleton_class.prepend(Datadog::Core::Utils::AtForkMonkeyPatch::ProcessMonkeyPatch)
    expect { process._fork }.to raise_error(Errno::EAGAIN)
    expect(identity).to eq(parent)
    send_trace(transport)
    transport.close
    request = agent.telemetry
    expect(request.fetch("body")["runtime_id"]).to eq(parent.first)
    expect(request_count(request)).to eq(2)
  end

  it "accepts parent sends while native workers are paused before the send drain" do
    exporter = nil
    allow(Datadog::Tracing::Transport::Native::TraceExporter).to receive(:_native_new).and_wrap_original do |method, **options|
      exporter = method.call(**options)
    end
    transport = build_transport
    exporter._native_before_fork
    send_trace(transport)
    exporter._native_after_fork_in_parent
    transport.close
    expect(request_count(agent.telemetry)).to eq(1)
  ensure
    exporter&._native_after_fork_in_parent
  end

  it "keeps Ruby as the sole application lifecycle owner" do
    port = agent.port
    child = fork do
      WebMock.disable!
      Datadog.configure do |config|
        config.agent.host = "127.0.0.1"
        config.agent.port = port
        config.service = "native-telemetry-test"
        config.telemetry.enabled = true
        config.telemetry.metrics_enabled = true
        config.telemetry.heartbeat_interval_seconds = 3600
        config.tracing.native_transport = true
        config.remote.enabled = false
        config.profiling.enabled = false
      end
      Datadog::Tracing.trace("native.telemetry") {}
      Datadog.shutdown!
      agent.barrier
      exit! 0
    end
    requests = agent.read_until_barrier.select { |request| request.fetch("path").include?("apmtelemetry") }
    expect(Timeout.timeout(5) { Process.wait2(child).last }).to be_success
    payloads = requests.map { |request| JSON.parse([request.fetch("body")].pack("H*")) }
    types = payloads.flat_map do |payload|
      if payload["request_type"] == "message-batch"
        payload.fetch("payload").map { |item| item.fetch("request_type") }
      else
        [payload.fetch("request_type")]
      end
    end
    expect(types.count("app-started")).to eq(1)
    expect(types.count("app-closing")).to eq(1)
    expect(payloads.map { |payload| payload.fetch("runtime_id") }.uniq.size).to eq(1)
    expect(payloads.map { |payload| payload.fetch("seq_id") }).to all(be > 0)
    expect(payloads.to_json).to include("src_library:libdatadog")
  ensure
    NativeTransportForkIsolation.reap_process(child)
  end

  [[:enabled, false], [:metrics_enabled, false], [:agentless_enabled, true]].each do |option, value|
    it "does not emit native telemetry with #{option}=#{value}" do
      settings.telemetry.public_send("#{option}=", value)
      transport = build_transport
      send_trace(transport)
      transport.close
      expect(agent.drain.map { |request| request.fetch("path") }).not_to include(/apmtelemetry/)
    end
  end

  it "stops native telemetry when replacing an enabled transport with disabled settings" do
    transport = build_transport
    send_trace(transport)
    transport.close
    expect(request_count(agent.telemetry)).to eq(1)
    before = agent.requests.count { |request| request.fetch("path").include?("apmtelemetry") }
    settings.telemetry.enabled = false
    replacement = build_transport
    send_trace(replacement)
    replacement.close
    expect(agent.drain.count { |request| request.fetch("path").include?("apmtelemetry") }).to eq(before)
  end

  it "does not emit native telemetry for a directly constructed transport when tracing is disabled" do
    settings.tracing.enabled = false
    transport = build_transport
    send_trace(transport)
    transport.close
    expect(agent.drain.map { |request| request.fetch("path") }).not_to include(/apmtelemetry/)
  end

  it "discards pending metrics when telemetry is disabled before close" do
    transport = build_transport
    send_trace(transport)
    settings.telemetry.enabled = false
    transport.close
    expect(agent.drain.map { |request| request.fetch("path") }).not_to include(/apmtelemetry/)
  end

  it "rejects child sends and discards inherited data if Ruby child identity lookup fails" do
    transport = build_transport
    parent = identity.first
    send_trace(transport)
    allow(Datadog::Core::Environment::Identity).to receive(:root_runtime_id).and_raise("identity unavailable")
    child = fork do
      span = Datadog::Tracing::Span.new("child", id: 123, trace_id: 456)
      trace = Datadog::Tracing::TraceSegment.new([span], id: 456, root_span_id: 123)
      response = transport.send_traces([trace]).first
      transport.close
      exit!(response.internal_error? ? 0 : 1)
    end
    expect(Timeout.timeout(5) { Process.wait2(child).last }).to be_success
    transport.close
    request = agent.telemetry
    expect(request.fetch("body")["runtime_id"]).to eq(parent)
    expect(request_count(request)).to eq(1)
    expect(agent.drain.count { |item| item.fetch("path").include?("apmtelemetry") }).to eq(1)
  ensure
    NativeTransportForkIsolation.reap_process(child)
  end

  context "with an in-flight telemetry request" do
    let(:agent) { TelemetryAgent.new(block_telemetry: true) }

    before { settings.telemetry.heartbeat_interval_seconds = 0.05 }

    it "allows Ruby threads to release a request while fork preparation waits" do
      transport = build_transport
      send_trace(transport)
      first = agent.telemetry
      forker = Thread.current
      releaser = Thread.new do
        Thread.pass until forker.status == "sleep"
        agent.release
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      child = fork { exit! 0 }
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
      expect(Process.wait2(child).last).to be_success
      expect(releaser.join(5)).to eq(releaser)
      send_trace(transport)
      second = agent.telemetry
      expect(second.fetch("body")["runtime_id"]).to eq(first.fetch("body")["runtime_id"])
      expect(second.fetch("body")["seq_id"]).to be > first.fetch("body")["seq_id"]
      agent.release
    ensure
      NativeTransportForkIsolation.reap_process(child)
    end

    it "bounds explicit shutdown against an unresponsive Agent" do
      transport = build_transport
      send_trace(transport)
      agent.telemetry
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      transport.close
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
    end

    it "bounds fork preparation by the active telemetry request timeout" do
      transport = build_transport
      send_trace(transport)
      agent.telemetry
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      child = fork { exit! 0 }
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 6
      expect(Process.wait2(child).last).to be_success
    ensure
      NativeTransportForkIsolation.reap_process(child)
    end
  end

  context "when a trace send is cancelled" do
    let(:agent) { TelemetryAgent.new(block_trace: true) }

    it "keeps the telemetry worker available for later sends" do
      transport = build_transport
      sender = Thread.new { send_trace(transport) }
      agent.request(%r{\A/v0\.})
      sender.kill
      expect(sender.join(3)).to eq(sender)
      agent.release
      send_trace(transport)
      transport.close
      expect(request_count(agent.telemetry)).to be >= 1
    ensure
      sender&.kill
      sender&.join(3)
    end
  end

  context "with a Unix-domain Agent socket" do
    let(:directory) { Dir.mktmpdir("native-telemetry") }
    let(:agent) { TelemetryAgent.new(socket_path: File.join(directory, "agent.sock")) }

    after { FileUtils.remove_entry(directory) }

    it "uses the trace Agent socket for native telemetry" do
      transport = build_transport
      send_trace(transport)
      transport.close
      expect(request_count(agent.telemetry)).to eq(1)
    end
  end
end
