# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'ddtrace'

class TracingTraceBenchmark
  module NoopWriter
    def write(trace)
      # no-op
    end
  end

  module NoopAdapter
    Response = Struct.new(:code, :body)

    def open
      Response.new(200)
    end
  end

  def benchmark_no_writer
    ::Datadog::Tracing::Writer.prepend(NoopWriter)

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.001, warmup: 0 } : { time: 10.5, warmup: 2 }
      x.config(**benchmark_time)

      def trace(x, depth)
        x.report(
          "#{depth} span trace - no writer",
          (depth.times.map { "Datadog::Tracing.trace('op.name') {" } + depth.times.map { "}" }).join
        )
      end

      trace(x, 1)
      trace(x, 10)
      trace(x, 100)

      x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_no_network
    ::Datadog::Core::Transport::HTTP::Adapters::Net.prepend(NoopAdapter)

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.001, warmup: 0 } : { time: 10.5, warmup: 2 }
      x.config(**benchmark_time)

      def trace(x, depth)
        x.report(
          "#{depth} span trace - no network",
          (depth.times.map { "Datadog::Tracing.trace('op.name') {" } + depth.times.map { "}" }).join
        )
      end

      trace(x, 1)
      trace(x, 10)
      trace(x, 100)

      x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def benchmark_to_digest
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.001, warmup: 0 } : { time: 10.5, warmup: 2 }
      x.config(**benchmark_time)

      Datadog::Tracing.trace('op.name') do |span, trace|
        x.report("trace.to_digest") do
          trace.to_digest
        end
      end

      x.save! "#{__FILE__}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

def run_benchmark(&block)
  # Forking to avoid monkey-patching leaking between benchmarks
  pid = fork { block.call }
  _, status = Process.wait2(pid)

  raise "Benchmark failed with status #{status}" unless status.success?
end

TracingTraceBenchmark.new.instance_exec do
  run_benchmark { benchmark_no_writer }
  run_benchmark { benchmark_no_network }
  run_benchmark { benchmark_to_digest }
end
