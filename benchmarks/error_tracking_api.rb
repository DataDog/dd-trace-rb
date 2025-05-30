# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'
require 'datadog'
require 'benchmark'
require 'net/http'
require 'webmock'
class ErrorTrackingApiBenchmark
  module NoopWriter
    def write(trace)
      # no-op
    end
  end

  # @param [Integer] time in seconds. The default is 20 seconds.Because benchmark-ips tries to run one iteration
  #   per 100ms, this means we'll have around 200 samples (give or take a small margin of error).
  # @param [Integer] warmup in seconds. The default is 2 seconds.
  def benchmark_time(time: 20, warmup: 2)
    VALIDATE_BENCHMARK_MODE ? { time: 0.001, warmup: 0 } : { time: time, warmup: warmup }
  end

  def initialize
    ::Datadog::Tracing::Writer.prepend(NoopWriter)

    # Enable WebMock but allow connections to the Datadog agent
    WebMock.disable_net_connect!(allow: ['testagent:9126', 'localhost:9126', '127.0.0.1:9126'])

    WebMock.stub_request(:any, 'http://example.com/test').to_return do
      # Sleep for 50ms to simulate network latency
      sleep(0.05)

      { status: 200, body: 'OK' }
    end
  end

  def benchmark_with_http_request_simulation_no_error_tracking
    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report('without error tracking with http') do
        Datadog::Tracing.trace('http.request') do
          Net::HTTP.get_response(URI('http://example.com/test'))
          begin
            raise 'Test error'
          rescue
            # do nothing
          end
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

      x.report('error tracking with http - all') do
        Datadog::Tracing.trace('http.request') do
          Net::HTTP.get_response(URI('http://example.com/test'))
          begin
            raise 'Test error'
          rescue
            # do nothing
          end
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

      x.report('error tracking with http - user code only') do
        Datadog::Tracing.trace('http.request') do
          Net::HTTP.get_response(URI('http://example.com/test'))
          begin
            raise 'Test error'
          rescue
            # do nothing
          end
        end
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_with_http_request_simulation_third_party
    Datadog.configure do |c|
      c.error_tracking.handled_errors = 'user'
    end

    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report('error tracking with http - third_party only') do
        Datadog::Tracing.trace('http.request') do
          Net::HTTP.get_response(URI('http://example.com/test'))
          begin
            raise 'Test error'
          rescue
            # do nothing
          end
        end
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
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

ErrorTrackingApiBenchmark.new.instance_exec do
  run_benchmark { benchmark_with_http_request_simulation_no_error_tracking }
  run_benchmark { benchmark_with_http_request_simulation_all }
  run_benchmark { benchmark_with_http_request_simulation_user }
  run_benchmark { benchmark_with_http_request_simulation_third_party }
end

# Clean up WebMock stubs after all benchmarks are finished
WebMock.disable!
