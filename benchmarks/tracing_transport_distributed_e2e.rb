# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV["VALIDATE_BENCHMARK"] == "true"

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative "benchmarks_helper"
require "socket"

# End-to-end transport benchmark simulating a distributed application.
#
# Each request traverses a chain of forked Ruby service processes. Every
# service extracts the incoming trace context, continues the trace, creates
# spans, injects the resulting context into the downstream request, and sends
# its trace segment to a shared mock agent using a synchronous writer.
#
# Usage:
#   bundle exec ruby benchmarks/tracing_transport_distributed_e2e.rb
class TracingTransportDistributedE2EBenchmark
  SERVICE_COUNT = 2

  def initialize
    Datadog.logger.level = Logger::FATAL
    @mock_agent = MockAgent.new
    @chains = []
  end

  def run_benchmark
    benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 30, warmup: 5}
    results_file = "#{File.basename(__FILE__, ".rb")}-results.json"
    # `save!` reloads existing results into the comparison, so start each repetition clean.
    File.delete(results_file) if !VALIDATE_BENCHMARK_MODE && File.file?(results_file)
    http_chain = build_chain(:http)
    native_chain = build_chain(:native) if native_supported?

    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report(benchmark_name("HTTP")) do
        request(http_chain.port)
      end

      if native_chain
        x.report(benchmark_name("Native")) do
          request(native_chain.port)
        end
      end

      x.save! results_file unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  ensure
    @chains.reverse_each(&:stop)
    @mock_agent.stop
  end

  private

  def benchmark_name(transport)
    "distributed trace across #{SERVICE_COUNT} services - #{transport} transport"
  end

  def build_chain(mode)
    chain = ServiceChain.new(
      mode: mode,
      agent_port: @mock_agent.port,
      service_count: SERVICE_COUNT,
    )
    @chains << chain
    chain
  end

  def native_supported?
    require "datadog/tracing/transport/native"

    return true if Datadog::Tracing::Transport::Native.supported?

    puts "WARNING: Native transport not available: #{Datadog::Tracing::Transport::Native::UNSUPPORTED_REASON}"
    puts "Skipping native transport benchmark."
    false
  end

  def request(port, headers = {})
    socket = TCPSocket.new("127.0.0.1", port)
    socket.write("GET /work HTTP/1.1\r\n")
    socket.write("Host: 127.0.0.1\r\n")
    headers.each { |key, value| socket.write("#{key}: #{value}\r\n") }
    socket.write("Connection: close\r\n\r\n")
    response = socket.read
    raise "Service request failed" unless response.start_with?("HTTP/1.1 200")
  ensure
    socket&.close
  end

  class ServiceChain
    attr_reader :port

    def initialize(mode:, agent_port:, service_count:)
      @services = []
      downstream_port = nil

      service_count.downto(1) do |service_number|
        service = Service.new(
          mode: mode,
          agent_port: agent_port,
          downstream_port: downstream_port,
          name: "benchmark-service-#{service_number}",
        )
        @services << service
        downstream_port = service.port
      end

      @port = downstream_port
    rescue
      stop
      raise
    end

    def stop
      @services&.each(&:stop)
    end
  end

  class Service
    attr_reader :port

    def initialize(mode:, agent_port:, downstream_port:, name:)
      server = TCPServer.new("127.0.0.1", 0)
      @port = server.addr[1]
      ready_reader, ready_writer = IO.pipe

      @pid = fork do
        ready_reader.close
        configure_tracer(mode, agent_port)
        ready_writer.write("ready")
        ready_writer.close

        loop do
          client = server.accept
          handle_request(client, downstream_port, name)
        rescue Interrupt
          break
        end
      end

      server.close
      ready_writer.close
      unless ready_reader.read == "ready"
        Process.wait(@pid)
        raise "Service #{name} failed to start"
      end
    ensure
      ready_reader&.close
      ready_writer&.close
    end

    def stop
      Process.kill("TERM", @pid)
      Process.wait(@pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    private

    def configure_tracer(mode, agent_port)
      Datadog.configure do |c|
        c.logger.level = Logger::FATAL
        c.tracing.enabled = true
        c.tracing.native_transport = (mode == :native)
        c.tracing.test_mode.enabled = true
        c.tracing.test_mode.async = false
        c.tracing.test_mode.writer_options = {
          transport: build_transport(mode, agent_port),
        }
      end
    end

    def build_transport(mode, agent_port)
      agent_url = "http://127.0.0.1:#{agent_port}"

      case mode
      when :http
        agent_settings = Struct.new(:url, :adapter, :ssl, :hostname, :port, :uds_path, :timeout_seconds)
          .new(agent_url, :net_http, false, "127.0.0.1", agent_port, nil, 5)
        Datadog::Tracing::Transport::HTTP.default(
          agent_settings: agent_settings,
          logger: Logger.new(File::NULL),
        )
      when :native
        require "datadog/tracing/transport/native"
        agent_settings = Struct.new(:url).new(agent_url)
        Datadog::Tracing::Transport::Native::Transport.new(
          agent_settings: agent_settings,
          logger: Logger.new(File::NULL),
        )
      end
    end

    def handle_request(client, downstream_port, name)
      headers = read_headers(client)
      digest = Datadog::Tracing::Contrib::HTTP.extract(headers)

      Datadog::Tracing.continue_trace!(digest) do
        Datadog::Tracing.trace("service.request", service: name, resource: "GET /work") do
          call_downstream(downstream_port) if downstream_port
        end
      end

      client.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    ensure
      client&.close
    end

    def read_headers(client)
      client.gets
      headers = {}

      while (line = client.gets) && line != "\r\n"
        key, value = line.split(":", 2)
        headers[key.downcase] = value.strip
      end

      headers
    end

    def call_downstream(port)
      headers = {}
      Datadog::Tracing::Contrib::HTTP.inject(Datadog::Tracing.active_trace.to_digest, headers)

      socket = TCPSocket.new("127.0.0.1", port)
      socket.write("GET /work HTTP/1.1\r\n")
      socket.write("Host: 127.0.0.1\r\n")
      headers.each { |key, value| socket.write("#{key}: #{value}\r\n") }
      socket.write("Connection: close\r\n\r\n")
      response = socket.read
      raise "Downstream service request failed" unless response.start_with?("HTTP/1.1 200")
    ensure
      socket&.close
    end
  end

  class MockAgent
    attr_reader :port

    def initialize
      server = TCPServer.new("127.0.0.1", 0)
      @port = server.addr[1]

      @pid = fork do
        body = '{"rate_by_service":{"service:,env:":1.0}}'
        response = "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n" \
                   "Content-Type: application/json\r\nConnection: close\r\n\r\n#{body}"

        loop do
          client = server.accept
          begin
            client.gets
            content_length = 0
            while (line = client.gets) && line != "\r\n"
              content_length = line.split(":", 2).last.to_i if line.downcase.start_with?("content-length:")
            end
            client.read(content_length) if content_length > 0
            client.write(response)
          rescue IOError, SystemCallError
            nil
          ensure
            client.close
          end
        rescue Interrupt
          break
        end
      end

      server.close
    end

    def stop
      Process.kill("TERM", @pid)
      Process.wait(@pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end
end

puts "Current pid is #{Process.pid}"

TracingTransportDistributedE2EBenchmark.new.run_benchmark
