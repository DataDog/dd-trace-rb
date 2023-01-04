# frozen_string_literal: true
# typed: false

# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'ddtrace'
require 'webrick'
require_relative 'dogstatsd_reporter'

class TracingHttpTransportBenchmark
  def initialize
    @port = Datadog::Transport::HTTP::DO_NOT_USE_ENVIRONMENT_AGENT_SETTINGS.port
    @transport = Datadog::Transport::HTTP.default
    @spans = test_traces(50)
  end

  def start_fake_webserver
    ready_queue = Queue.new

    require 'webrick'

    server = WEBrick::HTTPServer.new(
      Port: @port,
      StartCallback: -> { ready_queue.push(1) }
    )
    server_proc = proc do |req, res|
      res.body = '{}'
    end

    server.mount_proc('/', &server_proc)
    Thread.new { server.start }
    ready_queue.pop
  end

  # Return some test traces
  def test_traces(n, service: 'test-app', resource: '/traces', type: 'web')
    traces = []

    n.times do
      trace_op = Datadog::Tracing::TraceOperation.new

      trace_op.measure('client.testing', service: service, resource: resource, type: type) do
        trace_op.measure('client.testing', service: service, resource: resource, type: type) do
        end
      end

      traces << trace_op.flush!
    end

    traces
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 70, warmup: 2 }
      x.config(**benchmark_time, suite: report_to_dogstatsd_if_enabled_via_environment_variable(benchmark_name: 'tracing_http_transport'))

      x.report("http_transport #{ENV['CONFIG']}") do
        run_once
      end

      x.save! 'tmp/tracing-http-transport-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def run_forever
    while true
      100.times { run_once }
      print '.'
    end
  end

  def run_once
    success = @transport.send_traces(@spans)

    raise('Unexpected: Export failed') unless success
  end
end

puts "Current pid is #{Process.pid}"

TracingHttpTransportBenchmark.new.instance_exec do
  if ARGV.include?('--forever')
    run_forever
  else
    run_benchmark
  end
end
