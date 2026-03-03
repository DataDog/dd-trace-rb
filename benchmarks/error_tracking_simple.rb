# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'
require 'datadog'
require 'benchmark'
require 'net/http'
require 'webrick'

class ErrorTrackingSimpleBenchmark
  module NoopWriter
    def write(trace)
      # no-op
    end
  end

  # @param [Integer] time in seconds. The default is 12 seconds. Because benchmark-ips tries to
  # run one iteration per 100ms, this means we'll have around 120 samples
  # (give or take a small margin of error).
  # @param [Integer] warmup in seconds. The default is 2 seconds.
  def benchmark_time(time: 12, warmup: 2)
    VALIDATE_BENCHMARK_MODE ? {time: 0.001, warmup: 0} : {time: time, warmup: warmup}
  end

  def initialize
    ::Datadog::Tracing::Writer.prepend(NoopWriter)
  end

  def benchmark_simple_no_error_tracking(with_error: false)
    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report("without error tracking, with_error=#{with_error}") do
        Datadog::Tracing.trace('test.operation') do
          raise 'Test error' if with_error
        rescue
          # do nothing
        end
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_simple_all(with_error: false)
    Datadog.configure do |c|
      c.error_tracking.handled_errors = 'all'
    end

    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report("error tracking, with_error=#{with_error} - all") do
        Datadog::Tracing.trace('test.operation') do
          raise 'Test error' if with_error
        rescue
          # do nothing
        end
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_simple_user(with_error: false)
    Datadog.configure do |c|
      c.error_tracking.handled_errors = 'user'
    end

    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report("error tracking, with_error=#{with_error} - user code only") do
        Datadog::Tracing.trace('test.operation') do
          raise 'Test error' if with_error
        rescue
          # do nothing
        end
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_simple_third_party(with_error: false)
    Datadog.configure do |c|
      c.error_tracking.handled_errors = 'third_party'
    end

    Benchmark.ips do |x|
      x.config(**benchmark_time)

      x.report("error tracking, with_error=#{with_error} - third_party only") do
        Datadog::Tracing.trace('test.operation') do
          raise 'Test error' if with_error
        rescue
          # do nothing
        end
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

def run_benchmark(&block)
  if VALIDATE_BENCHMARK_MODE
    block.call
  else
    # Forking to avoid monkey-patching leaking between benchmarks
    pid = fork(&block)
    _, status = Process.wait2(pid)

    raise "Benchmark failed with status #{status}" unless status.success?
  end
end

ErrorTrackingSimpleBenchmark.new.instance_exec do
  run_benchmark { benchmark_simple_no_error_tracking }
  run_benchmark { benchmark_simple_no_error_tracking(with_error: true) }
  run_benchmark { benchmark_simple_all }
  run_benchmark { benchmark_simple_all(with_error: true) }
  run_benchmark { benchmark_simple_third_party }
  run_benchmark { benchmark_simple_third_party(with_error: true) }
  run_benchmark { benchmark_simple_user }
  run_benchmark { benchmark_simple_user(with_error: true) }
end
