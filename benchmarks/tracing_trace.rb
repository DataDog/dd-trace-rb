# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'

# Load the local version of the gem
lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddtrace'

class TracingTraceBenchmark
  module FauxWriter
    def write(trace)
      # no-op
    end

    ::Datadog::Tracing::Writer.prepend(self)
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.001, warmup: 0 } : { time: 10.5, warmup: 2 }
      x.config(**benchmark_time)

      def trace(x, depth)
        x.report(
          "#{depth} span trace",
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
end

puts "Current pid is #{Process.pid}"

TracingTraceBenchmark.new.instance_exec do
  run_benchmark
end
