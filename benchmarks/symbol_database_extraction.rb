#
# Symbol Database extraction benchmark.
#
# Generates 2500 user-code classes in a tmpdir, requires them, then runs
# Extractor#extract_all once and captures memory + CPU + wall time.
#
# Acceptance thresholds (from projects/symdb/requirements.md):
#   - memory overhead during extraction < 50 MB
#   - CPU overhead during extraction    < 5%
#
# Output: symbol_database_extraction-results.json
#
# Notes on measurement:
#   - Memory: VmRSS from /proc/self/status, sampled by a thread at ~10ms cadence
#     during extraction. Overhead = peak − baseline (post-GC.start).
#   - CPU: (utime + stime) / wall time, expressed as percent of one core. The
#     5% threshold is interpretable only when amortized over a long-running
#     process; a single one-shot extraction will report near 100% single-core
#     utilisation by construction. The harness emits the raw numbers and the
#     results doc decides PASS/FAIL.
#

VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'fileutils'
require 'json'
require 'logger'
require 'tmpdir'

require 'datadog/symbol_database/extractor'

class SymbolDatabaseExtractionBenchmark
  CLASS_COUNT = VALIDATE_BENCHMARK_MODE ? 10 : 2500

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

    baseline_rss_kb = read_rss_kb
    baseline_times = Process.times
    baseline_gc = GC.stat

    peak_rss_kb = baseline_rss_kb
    sampler_done = false
    sampler = Thread.new do
      until sampler_done
        rss = read_rss_kb
        peak_rss_kb = rss if rss > peak_rss_kb
        sleep 0.01
      end
    end

    wall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    scopes = extractor.extract_all
    wall_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    sampler_done = true
    sampler.join

    final_times = Process.times
    final_gc = GC.stat

    wall_time = wall_end - wall_start
    cpu_time = (final_times.utime + final_times.stime) -
      (baseline_times.utime + baseline_times.stime)
    cpu_percent = (wall_time > 0) ? (cpu_time / wall_time) * 100.0 : 0.0

    {
      wall_time_seconds: wall_time,
      cpu_time_seconds: cpu_time,
      cpu_percent: cpu_percent,
      memory_baseline_kb: baseline_rss_kb,
      memory_peak_kb: peak_rss_kb,
      memory_overhead_kb: peak_rss_kb - baseline_rss_kb,
      heap_live_slots_baseline: baseline_gc[:heap_live_slots],
      heap_live_slots_peak: final_gc[:heap_live_slots],
      file_scope_count: scopes.size
    }
  end

  def read_rss_kb
    File.read('/proc/self/status').match(/VmRSS:\s+(\d+) kB/)[1].to_i
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
