# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV["VALIDATE_BENCHMARK"] == "true"

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative "benchmarks_helper"

# This benchmark measures the performance of allocation profiling
#
# Set HEAP_SAMPLES=true to also enable heap profiling on top of it, which additionally exercises the heap recorder
# from inside the allocation tracepoint. Heap live size follows HEAP_SAMPLES unless HEAP_SIZE=false is set.
HEAP_SAMPLES = ENV["HEAP_SAMPLES"] == "true"
HEAP_SIZE = ENV.fetch("HEAP_SIZE", HEAP_SAMPLES.to_s) == "true"
# Only decorate the report name when heap profiling is on, so the default benchmark keeps reporting under the same
# name as before (and thus stays comparable with previously recorded results).
HEAP_CONFIG_SUFFIX = HEAP_SAMPLES ? " heap_samples=#{HEAP_SAMPLES} heap_size=#{HEAP_SIZE}" : ""

class ExportToFile
  PPROF_PREFIX = ENV.fetch("DD_PROFILING_PPROF_PREFIX", "profiler-allocation")

  def export(flush)
    File.write("#{PPROF_PREFIX}#{flush.start.strftime("%Y%m%dT%H%M%SZ")}.pprof", flush.encoded_profile._native_bytes)
    true
  end
end

class ProfilerAllocationBenchmark
  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report("Allocations (baseline)", "BasicObject.new")

      x.save! "#{File.basename(__FILE__, ".rb")}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    Datadog.configure do |c|
      c.profiling.enabled = true
      c.profiling.allocation_enabled = true
      c.profiling.advanced.gc_enabled = false
      c.profiling.advanced.experimental_heap_enabled = HEAP_SAMPLES
      c.profiling.advanced.experimental_heap_size_enabled = HEAP_SIZE
      c.profiling.exporter.transport = ExportToFile.new unless VALIDATE_BENCHMARK_MODE
    end
    Datadog::Profiling.wait_until_running

    3.times { GC.start }

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report("Allocations (#{ENV["CONFIG"]})#{HEAP_CONFIG_SUFFIX}", "BasicObject.new")

      x.save! "#{File.basename(__FILE__, ".rb")}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

ProfilerAllocationBenchmark.new.instance_exec do
  run_benchmark
end
