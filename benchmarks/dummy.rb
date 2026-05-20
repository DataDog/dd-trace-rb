# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'

# Minimal benchmark that emits a benchmark-ips-shaped result JSON.
# Used to verify the microbenchmarks: [other] CI job and its analyzer
# pipeline are healthy end-to-end without depending on any product code path.
class DummyBenchmark
  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(**benchmark_time)

      x.report('dummy - integer add') { 1 + 1 }

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

DummyBenchmark.new.instance_exec do
  run_benchmark
end
