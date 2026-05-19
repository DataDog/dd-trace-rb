#
# Symbol Database background-impact benchmark.
#
# Measures how SymDB extraction running on a background thread impacts a
# concurrent main-thread CPU-bound workload. The signal is the ops/sec drop
# between two Benchmark.ips reports:
#
#   workload_baseline           — workload alone, nothing in the background
#   workload_during_extraction  — same workload while a background thread
#                                 runs Extractor#extract_all in a loop
#
# A regression that removes the in-extractor throttle (or otherwise lets
# extraction monopolize the GVL) shows up as an ops/sec drop on the second
# report. Regression detection is done by bp-runner via the gitlab
# microbenchmarks pipeline — see .gitlab/benchmarks.yml. No threshold logic
# lives in this file.
#
# This is the synthetic-workload counterpart to the request-load test that
# requirements.md item 23 ("Extraction must not block the application's
# request handling") asks for. A pure-Ruby CPU-bound workload is sufficient:
# the impact vector is GVL hold time during ObjectSpace traversal.
#
# Design choices:
#   - Background extraction is driven directly via Extractor#extract_all on
#     a benchmark-owned Thread rather than through Component#start_upload.
#     The GVL contention on the main thread is identical either way, and this
#     avoids the 5s debounce, force_upload plumbing, and uploader stubbing
#     that Component would require.
#   - The bg thread loops on extract_all for the full duration of the
#     treatment report so contention is sustained — every measured iteration
#     happens while extraction is in flight.
#

VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'logger'
require 'tmpdir'

require 'datadog/symbol_database/extractor'
require_relative 'benchmarks_ips_patch'

class SymbolDatabaseBackgroundImpactBenchmark
  CLASS_COUNT = VALIDATE_BENCHMARK_MODE ? 10 : 2500

  class StubSettings
    def method_missing(_name, *_args, **_kwargs)
      self
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end

  def run
    Dir.mktmpdir('symdb_bgimpact_') do |dir|
      generate_class_files(dir)
      load_class_files(dir)
      run_benchmark
    end
  end

  private

  def generate_class_files(dir)
    CLASS_COUNT.times do |i|
      File.write(File.join(dir, "bgimpact_class_#{i}.rb"), class_source(i))
    end
  end

  def class_source(i)
    name = "BgImpactClass#{i}"
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
      require File.join(dir, "bgimpact_class_#{i}")
    end
  end

  def extractor
    @extractor ||= Datadog::SymbolDatabase::Extractor.new(
      logger: Logger.new(File::NULL),
      settings: StubSettings.new,
    )
  end

  # Non-allocating arithmetic workload. Pure integer ops produce no garbage,
  # so GC frequency doesn't drift between reports and the ops/sec drop
  # reflects GVL contention from extraction rather than GC variability.
  def workload_op
    acc = 0x12345
    200.times do
      acc = ((acc * 1_103_515_245) + 12_345) & 0x7fff_ffff
    end
    acc
  end

  def run_benchmark
    benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.001, warmup: 0} : {time: 12, warmup: 2}
    output_basename = File.basename(__FILE__, '.rb')

    # Baseline report — workload alone.
    Benchmark.ips do |x|
      x.config(**benchmark_time)
      x.report('workload_baseline') { workload_op }
      x.save! "#{output_basename}-baseline-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    # Treatment report — workload while a background thread runs extract_all
    # in a tight loop, producing sustained GVL contention.
    @stop_bg = false
    bg = Thread.new do
      extractor.extract_all until @stop_bg
    end

    begin
      Benchmark.ips do |x|
        x.config(**benchmark_time)
        x.report('workload_during_extraction') { workload_op }
        x.save! "#{output_basename}-treatment-results.json" unless VALIDATE_BENCHMARK_MODE
        x.compare!
      end
    ensure
      @stop_bg = true
      bg.join
    end
  end
end

puts "Current pid is #{Process.pid}"

SymbolDatabaseBackgroundImpactBenchmark.new.run
