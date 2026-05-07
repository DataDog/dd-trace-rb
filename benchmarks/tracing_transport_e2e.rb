# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'
require 'socket'

# End-to-end benchmark comparing native vs HTTP trace transport using
# the full `Datadog::Tracing.trace` pipeline.
#
# Unlike `tracing_transport.rb` which benchmarks `send_traces` in
# isolation with synthetic `TraceSegment`s, this benchmark exercises
# the entire path: `Datadog::Tracing.trace` -> span creation -> trace
# flush -> transport -> mock agent.
#
# Uses `SyncWriter` so each `trace {}` block completes a full
# round-trip synchronously, giving stable per-iteration measurements.
#
# Usage:
#   bundle exec ruby benchmarks/tracing_transport_e2e.rb
class TracingTransportE2EBenchmark
  # @param [Integer] depth number of nested spans per trace
  def initialize(depth: 10)
    Datadog.logger.level = Logger::FATAL
    @depth = depth
    @mock_agent = MockAgent.new
    @trace_code = build_trace_code(depth)
  end

  def run_benchmark
    benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 12, warmup: 2}

    Benchmark.ips do |x|
      x.config(**benchmark_time)

      configure_tracer(:http)
      x.report("#{@depth} span trace - HTTP transport") do
        eval(@trace_code) # standard:disable Security/Eval
      end

      configure_tracer(:native)
      x.report("#{@depth} span trace - Native transport") do
        eval(@trace_code) # standard:disable Security/Eval
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  ensure
    Datadog::Tracing.shutdown!
    @mock_agent.stop
  end

  private

  def build_trace_code(depth)
    opens = depth.times.map { |i| "Datadog::Tracing.trace('op.#{i}') {" }
    closes = depth.times.map { '}' }
    (opens + closes).join
  end

  def agent_url
    "http://127.0.0.1:#{@mock_agent.port}"
  end

  def configure_tracer(mode)
    Datadog.configure do |c|
      c.logger.level = Logger::FATAL
      c.tracing.enabled = true
      c.tracing.native_transport = (mode == :native)
      c.tracing.test_mode.enabled = true
      c.tracing.test_mode.async = false # forces SyncWriter
      c.tracing.test_mode.writer_options = {
        transport: build_transport(mode),
      }
    end
  end

  def build_transport(mode)
    case mode
    when :http
      agent_settings = Struct.new(:url, :adapter, :ssl, :hostname, :port, :uds_path, :timeout_seconds)
        .new(agent_url, :net_http, false, '127.0.0.1', @mock_agent.port, nil, 5)
      Datadog::Tracing::Transport::HTTP.default(
        agent_settings: agent_settings,
        logger: Logger.new('/dev/null'),
      )
    when :native
      require 'datadog/tracing/transport/native'
      agent_settings = Struct.new(:url).new(agent_url)
      Datadog::Tracing::Transport::Native::Transport.new(
        agent_settings: agent_settings,
        logger: Logger.new('/dev/null'),
      )
    end
  end

  # Mock agent: forked process with threaded request handling.
  class MockAgent
    attr_reader :port

    def initialize
      server = TCPServer.new('127.0.0.1', 0)
      @port = server.addr[1]

      @pid = fork do
        body = '{"rate_by_service":{"service:,env:":1.0}}'
        response = "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n" \
                   "Content-Type: application/json\r\n\r\n#{body}"
        queue = Queue.new

        4.times do
          Thread.new do
            loop do
              client = queue.pop
              begin
                request_line = client.gets
                next client.close if request_line.nil?

                content_length = 0
                while (line = client.gets) && line != "\r\n"
                  content_length = line.split(': ', 2).last.to_i if line.downcase.start_with?('content-length')
                end
                client.read(content_length) if content_length > 0

                client.print response
              rescue # rubocop:disable Lint/SuppressedException
              ensure
                client.close rescue nil
              end
            end
          end
        end

        loop do
          client = server.accept rescue break
          queue.push(client)
        end
      end

      server.close
    end

    def stop
      Process.kill('TERM', @pid) rescue nil
      Process.wait(@pid) rescue nil
    end
  end
end

puts "Current pid is #{Process.pid}"

TracingTransportE2EBenchmark.new(depth: 10).run_benchmark
