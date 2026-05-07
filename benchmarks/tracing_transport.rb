# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'
require 'socket'

# Compares the native trace transport (Rust via C FFI) against the default
# pure-Ruby HTTP transport.
#
# Both transports send traces to a minimal mock agent (TCP server) that
# accepts and discards payloads, so the benchmark measures serialization
# + transport overhead without real agent processing.
#
# Usage:
#   bundle exec ruby benchmarks/tracing_transport.rb
class TracingTransportBenchmark
  def initialize
    Datadog.logger.level = Logger::FATAL
    @mock_agent = MockAgent.new
    @traces = build_traces
  end

  def run_benchmark
    http_transport = build_http_transport
    native_transport = build_native_transport

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 12, warmup: 2}
      x.config(**benchmark_time)

      x.report("send_traces - HTTP") do
        http_transport.send_traces(@traces)
      end

      if native_transport
        x.report("send_traces - Native") do
          native_transport.send_traces(@traces)
        end
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  ensure
    @mock_agent.stop
  end

  private

  def build_traces(count: 10, spans_per_trace: 5)
    count.times.map do
      trace_id = rand(1 << 62)
      spans = spans_per_trace.times.map do |i|
        Datadog::Tracing::Span.new(
          "benchmark.op.#{i}",
          service: 'benchmark-svc',
          resource: "GET /bench/#{i}",
          type: 'web',
          id: rand(1 << 62),
          parent_id: i == 0 ? 0 : rand(1 << 62),
          trace_id: trace_id,
        ).tap do |span|
          span.set_tag('http.method', 'GET')
          span.set_tag('http.url', "/bench/#{i}")
          span.set_tag('http.status_code', '200')
          span.set_metric('_dd.measured', 1.0)
          span.set_metric('_sampling_priority_v1', 1.0)
        end
      end
      Datadog::Tracing::TraceSegment.new(
        spans,
        id: trace_id,
        root_span_id: spans.first.id
      )
    end
  end

  def agent_settings
    @agent_settings ||= Struct.new(:url).new("http://127.0.0.1:#{@mock_agent.port}")
  end

  def build_http_transport
    Datadog::Tracing::Transport::HTTP.default(
      agent_settings: agent_settings,
      logger: Logger.new('/dev/null'),
    )
  end

  def build_native_transport
    require 'datadog/tracing/transport/native'

    unless Datadog::Tracing::Transport::Native.supported?
      puts "WARNING: Native transport not available: #{Datadog::Tracing::Transport::Native::UNSUPPORTED_REASON}"
      puts "Skipping native transport benchmark."
      return nil
    end

    Datadog::Tracing::Transport::Native::Transport.new(
      agent_settings: agent_settings,
      logger: Logger.new('/dev/null'),
    )
  end

  # Minimal mock HTTP agent that accepts and discards trace payloads.
  #
  # Runs in a forked process to avoid GVL contention with the
  # benchmarked Ruby code.
  class MockAgent
    attr_reader :port

    def initialize
      # Bind before forking so the parent knows the port.
      server = TCPServer.new('127.0.0.1', 0)
      @port = server.addr[1]

      @pid = fork do
        # Child: serve requests with a small thread pool.
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

                # Drain headers + body
                content_length = 0
                while (line = client.gets) && line != "\r\n"
                  content_length = line.split(': ', 2).last.to_i if line.start_with?('Content-Length')
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

      # Parent: close our copy of the server socket.
      server.close
    end

    def stop
      Process.kill('TERM', @pid) rescue nil
      Process.wait(@pid) rescue nil
    end
  end
end

puts "Current pid is #{Process.pid}"

TracingTransportBenchmark.new.run_benchmark
