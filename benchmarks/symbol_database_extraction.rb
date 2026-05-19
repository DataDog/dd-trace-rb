#
# Symbol Database extraction benchmark.
#
# Generates 2500 user-code classes in a tmpdir, requires them, then measures
# Extractor#extract_all throughput via Benchmark.ips.
#
# The ops/sec from this benchmark is what the gitlab microbenchmarks pipeline
# tracks for regression detection (see .gitlab/benchmarks.yml — 5% PR comment,
# 20% merge block). Memory and CPU figures are printed once for human review
# but not fed into regression detection: bp-runner already detects throughput
# regressions on the ops/sec series, so duplicating that with hand-coded
# thresholds would be redundant.
#

VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'logger'
require 'tmpdir'

require 'datadog/symbol_database/extractor'
require_relative 'benchmarks_ips_patch'
require_relative 'support/memory_probe'

class SymbolDatabaseExtractionBenchmark
  CLASS_COUNT = VALIDATE_BENCHMARK_MODE ? 10 : 2500

  # Extractor stores @settings but extract_all does not consult it — modelled
  # after the double in spec/datadog/symbol_database/extractor_spec.rb.
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
      print_diagnostics
      run_benchmark
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

  def extractor
    @extractor ||= Datadog::SymbolDatabase::Extractor.new(
      logger: Logger.new(File::NULL),
      settings: StubSettings.new,
    )
  end

  # One-shot extract_all with memory + CPU instrumentation. For human review
  # only; the regression detector consumes the Benchmark.ips ops/sec below.
  def print_diagnostics
    return if VALIDATE_BENCHMARK_MODE

    3.times { GC.start }
    baseline_rss_kb = BenchmarkMemoryProbe.rss_kb
    baseline_times = Process.times

    peak_rss_kb = baseline_rss_kb
    stop_sampler = false
    sampler = Thread.new do
      until stop_sampler
        rss = BenchmarkMemoryProbe.rss_kb
        peak_rss_kb = rss if rss > peak_rss_kb
        sleep 0.01
      end
    end

    wall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    scopes = extractor.extract_all
    wall_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall_start

    stop_sampler = true
    sampler.join

    final_times = Process.times
    cpu_seconds = (final_times.utime + final_times.stime) -
      (baseline_times.utime + baseline_times.stime)
    cpu_percent_of_one_core = (wall_seconds > 0) ? (cpu_seconds / wall_seconds) * 100.0 : 0.0

    puts "# symbol_database extraction diagnostics (one shot, #{CLASS_COUNT} classes):"
    puts format("#   wall time:        %.3fs", wall_seconds)
    puts format("#   cpu time:         %.3fs (%.1f%% of one core)", cpu_seconds, cpu_percent_of_one_core)
    puts format("#   rss baseline:     %d kB", baseline_rss_kb)
    puts format("#   rss peak:         %d kB", peak_rss_kb)
    puts format("#   rss overhead:     %d kB", peak_rss_kb - baseline_rss_kb)
    puts format("#   file scopes:      %d", scopes.size)
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.001, warmup: 0} : {time: 12, warmup: 2}
      x.config(**benchmark_time)

      x.report('extract_all') do
        extractor.extract_all
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

SymbolDatabaseExtractionBenchmark.new.run
