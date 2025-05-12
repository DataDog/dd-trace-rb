# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'
require 'datadog'
require 'benchmark'
require 'net/http'
require 'webrick'

class ErrorTrackingApiBenchmark
  module NoopWriter
    def write(trace)
      # no-op
    end
  end

  # @param [Integer] time in seconds. The default is 12 seconds because having over 105 samples allows the
  #   benchmarking platform to calculate helpful aggregate stats. Because benchmark-ips tries to run one iteration
  #   per 100ms, this means we'll have around 120 samples (give or take a small margin of error).
  # @param [Integer] warmup in seconds. The default is 2 seconds.
  def benchmark_time(time: 20, warmup: 2)
    VALIDATE_BENCHMARK_MODE ? { time: 0.001, warmup: 0 } : { time: time, warmup: warmup }
  end

  def initialize
    ::Datadog::Tracing::Writer.prepend(NoopWriter)
    Thread.new do
      server.start
    end
  end

  def benchmark_with_http_request_simulation_no_error_tracking
    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report('without error tracking with http') do
        Datadog::Tracing.trace('http.request') do
          Net::HTTP.get_response(URI('http://localhost:8126/test'))
        end
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_with_http_request_simulation_all
    Datadog.configure do |c|
      c.error_tracking.handled_errors = 'all'
    end

    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report('error tracking with http - all features') do
        Datadog::Tracing.trace('http.request') do |span|
          Net::HTTP.get_response(URI('http://localhost:8126/test'))
        end
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_with_http_request_simulation_user
    Datadog.configure do |c|
      c.error_tracking.handled_errors = 'user'
    end

    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report('error tracking with http - user features only') do
        Datadog::Tracing.trace('http.request') do |span|
          Net::HTTP.get_response(URI('http://localhost:8126/test'))
        end
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  private

  def server
    WEBrick::HTTPServer.new(
      Port: 8126,
      Logger: WEBrick::Log.new(nil, WEBrick::Log::ERROR),
      AccessLog: []
    ).tap do |server|
      server.mount_proc('/test') do |_req, res|
        sleep 0.14 # Simulate 70ms request processing
        begin
          raise 'Test error'
        rescue
          # do nothing
        end
        res.status = 200
        res.body = 'OK'
      end
    end
  end
end

puts "Current pid is #{Process.pid}"

def run_benchmark(&block)
  # Forking to avoid monkey-patching leaking between benchmarks
  pid = fork(&block)
  _, status = Process.wait2(pid)

  raise "Benchmark failed with status #{status}" unless status.success?
end

ErrorTrackingInstrumentBenchmark.new.instance_exec do
  run_benchmark { benchmark_with_http_request_simulation_no_error_tracking }
  run_benchmark { benchmark_with_http_request_simulation_all }
  run_benchmark { benchmark_with_http_request_simulation_user }
end
