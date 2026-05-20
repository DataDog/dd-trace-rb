#
# Symbol Database extraction benchmark.
#
# Generates 2500 user-code classes in a tmpdir, requires them, then loops
# Extractor#extract_all back-to-back until WINDOW_SECONDS of wall time is
# accumulated, capturing memory + CPU + per-iteration timing.
#
# Acceptance thresholds (from projects/symdb/requirements.md):
#   - memory overhead during extraction < 50 MB
#   - CPU overhead during extraction    < 5%
#
# Output: symbol_database_extraction-results.json
#
# Notes on measurement:
#   - A single extract_all on 2500 classes finishes in ~0.3s without
#     throttling, which is too short to detect regressions smaller than
#     timing noise and too short for CPU% to be meaningful (a one-shot
#     measurement reports ~100% single-core by construction). The
#     benchmark therefore loops extract_all until ~12s of work
#     is accumulated and reports per-iteration percentiles plus aggregate
#     CPU%.
#   - extract_all is idempotent: it re-walks loaded modules each call and
#     produces a fresh scope list. Looping exercises the same code path,
#     amortizes GC and JIT effects, and gives variance estimates.
#   - Memory: RSS via BenchmarkMemoryProbe (ps -o rss=), sampled by a
#     thread at ~10ms cadence across the whole window. Overhead =
#     peak − baseline (post-GC.start).
#   - CPU: (utime + stime) / wall time across the whole window,
#     expressed as percent of one core.
#

VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'fileutils'
require 'json'
require 'logger'
require 'tmpdir'

require 'datadog/symbol_database/extractor'
require_relative 'support/memory_probe'

class SymbolDatabaseExtractionBenchmark
  CLASS_COUNT = VALIDATE_BENCHMARK_MODE ? 10 : 2500

  # Target accumulated wall time. Long enough that timing variance is a
  # small fraction of the measurement and CPU% is interpretable.
  WINDOW_SECONDS = VALIDATE_BENCHMARK_MODE ? 0.05 : 12

  # Minimum iterations even if the window is reached early — guarantees
  # enough samples for percentiles when extract_all is fast.
  MIN_ITERATIONS = VALIDATE_BENCHMARK_MODE ? 1 : 10

  # Safety cap so a degenerate fast path can't loop indefinitely.
  MAX_ITERATIONS = VALIDATE_BENCHMARK_MODE ? 5 : 5000

  # Settings stub. Extractor stores @settings but extract_all does not consult
  # it — modelled after the double in spec/datadog/symbol_database/extractor_spec.rb.
  class StubSettings
    def method_missing(_name, *_args, **_kwargs)
      self
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end

  def run
    Dir.mktmpdir('symdb_perf_') do |dir|
      generate_class_files(dir)
      load_class_files(dir)

      results = measure_extraction
      results[:class_count] = CLASS_COUNT
      results[:window_seconds] = WINDOW_SECONDS
      results[:ruby_version] = RUBY_VERSION
      results[:platform] = RUBY_PLATFORM

      emit(results)
    end
  end

  private

  def generate_class_files(dir)
    CLASS_COUNT.times do |i|
      File.write(File.join(dir, "perf_class_#{i}.rb"), class_source(i))
    end
  end

  def class_source(i)
    name = "PerfClass#{i}"
    <<~RUBY
      class #{name}
        CONST_VALUE = #{i}
        @@class_counter = 0

        def method_a(positional, keyword:, with_default: nil)
          [positional, keyword, with_default]
        end

        def method_b(*args, **kwargs)
          [args, kwargs]
        end

        def method_c(x, y, z)
          x + y + z
        end

        def method_d
          CONST_VALUE
        end

        def method_e(value)
          @@class_counter = value
        end
      end
    RUBY
  end

  def load_class_files(dir)
    CLASS_COUNT.times do |i|
      require File.join(dir, "perf_class_#{i}")
    end
  end

  def measure_extraction
    extractor = Datadog::SymbolDatabase::Extractor.new(
      logger: Logger.new(File::NULL),
      settings: StubSettings.new
    )

    3.times { GC.start }

    baseline_rss_kb = BenchmarkMemoryProbe.rss_kb
    baseline_times = Process.times
    baseline_gc = GC.stat

    peak_rss_kb = baseline_rss_kb
    sampler_done = false
    sampler = Thread.new do
      until sampler_done
        rss = BenchmarkMemoryProbe.rss_kb
        peak_rss_kb = rss if rss > peak_rss_kb
        sleep 0.01
      end
    end

    iter_walls = []
    iter_cpus = []
    last_scope_count = 0
    iterations = 0

    window_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    loop do
      iter_wall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iter_times_start = Process.times
      scopes = extractor.extract_all
      iter_wall_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iter_times_end = Process.times

      iter_walls << (iter_wall_end - iter_wall_start)
      iter_cpus << ((iter_times_end.utime + iter_times_end.stime) -
        (iter_times_start.utime + iter_times_start.stime))
      last_scope_count = scopes.size
      iterations += 1

      elapsed = iter_wall_end - window_start
      break if iterations >= MAX_ITERATIONS
      break if iterations >= MIN_ITERATIONS && elapsed >= WINDOW_SECONDS
    end
    window_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    sampler_done = true
    sampler.join

    final_times = Process.times
    final_gc = GC.stat

    total_wall = window_end - window_start
    total_cpu = (final_times.utime + final_times.stime) -
      (baseline_times.utime + baseline_times.stime)
    cpu_percent = (total_wall > 0) ? (total_cpu / total_wall) * 100.0 : 0.0

    {
      iterations: iterations,
      total_wall_time_seconds: total_wall,
      total_cpu_time_seconds: total_cpu,
      cpu_percent: cpu_percent,
      per_iteration_wall_seconds: percentiles(iter_walls),
      per_iteration_cpu_seconds: percentiles(iter_cpus),
      memory_baseline_kb: baseline_rss_kb,
      memory_peak_kb: peak_rss_kb,
      memory_overhead_kb: peak_rss_kb - baseline_rss_kb,
      heap_live_slots_baseline: baseline_gc[:heap_live_slots],
      heap_live_slots_peak: final_gc[:heap_live_slots],
      file_scope_count: last_scope_count
    }
  end

  def percentiles(samples)
    sorted = samples.sort
    {
      mean: samples.sum.fdiv(samples.size),
      min: sorted.first,
      p50: percentile(sorted, 0.50),
      p95: percentile(sorted, 0.95),
      p99: percentile(sorted, 0.99),
      max: sorted.last
    }
  end

  # Nearest-rank percentile on a pre-sorted array.
  def percentile(sorted, q)
    return sorted.first if sorted.size <= 1
    idx = (q * (sorted.size - 1)).round
    sorted[idx]
  end

  def emit(results)
    json = JSON.pretty_generate(results)
    puts json

    return if VALIDATE_BENCHMARK_MODE

    File.write("#{File.basename(__FILE__, '.rb')}-results.json", json)
  end
end

puts "Current pid is #{Process.pid}"

SymbolDatabaseExtractionBenchmark.new.run
