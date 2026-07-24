# Symbol Database baseline-matrix benchmark.
#
# Reproduces the shape of the 50/75/100% baseline-CPU matrix recorded in
# projects/symdb/reports/extraction-stress-test-2026-05-18.md (gobo Rails
# stress test) — within a pure-Ruby microbenchmark that fits in CI.
#
# The gobo report identified 75% baseline as the worst zone: handlers run at
# 75% of available CPU, leaving 25% headroom, and the extractor overruns that
# headroom and starts stealing from handlers — −31% RPS without throttle, ~1%
# with throttle. At 50% the extractor uses idle slack and barely touches
# handlers; at 100% the extractor is starved and again handlers barely feel
# it. The damage is concentrated in the middle.
#
# The existing symbol_database_background_impact.rb benchmark always runs the
# workload at maximum contention (no idle time), which is closer to the 100%
# baseline case where impact is small. This benchmark adds explicit baseline
# parametrization so the 75% bad zone is actually exercised.
#
# Workload model: a single Ruby thread alternates between `work_us` µs of
# CPU work and `idle_us` µs of sleep, per 1000-µs chunk. Ratio is the target
# baseline. ops/sec measures completed chunks per second.
#
# For each baseline, two arms run sequentially with a full GC pass between:
#   - no_extractor   — workload thread alone
#   - with_extractor — same workload + a bg thread looping on extract_all
#
# Known limitation: in a single-thread microbenchmark on a host with CPU
# frequency scaling, the no_extractor arm's CPU may idle down during the
# workload's sleep gaps; the with_extractor arm keeps the core hot via the
# bg thread, which can mask GVL contention or even produce negative drops
# at low baseline percentages. The 100% arm is unaffected (no idle slack)
# and is the most reliable regression signal. Absolute drop magnitudes
# here are not directly comparable to gobo's Rails table — for that, run
# the gobo stress rig.
#
# There is no in-script gate. Regression detection is done by bp-runner
# via the .gitlab/benchmarks microbenchmarks pipeline (PR-comment at 5%,
# merge-block at 20% ops/sec drop versus master).
#

VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'fileutils'
require 'json'
require 'logger'
require 'tmpdir'

require 'datadog/symbol_database/extractor'

class SymbolDatabaseBaselineMatrixBenchmark
  CLASS_COUNT = VALIDATE_BENCHMARK_MODE ? 10 : 2500

  # Window per arm. Long enough to cover several full extract_all iterations
  # (~1.7s each with throttle) so the workload sees both extract_all phases
  # and the brief gaps between them.
  WINDOW_SECONDS = VALIDATE_BENCHMARK_MODE ? 0.05 : 20

  BASELINES = [50, 75, 100].freeze

  class StubSettings
    def method_missing(_name, *_args, **_kwargs)
      self
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end

  def run
    Dir.mktmpdir('symdb_matrix_') do |dir|
      generate_class_files(dir)
      load_class_files(dir)

      @cpu_chunk_seconds = calibrate_cpu_chunk

      results = measure_matrix
      results[:class_count] = CLASS_COUNT
      results[:window_seconds] = WINDOW_SECONDS
      results[:cpu_chunk_seconds] = @cpu_chunk_seconds
      results[:baselines] = BASELINES
      results[:ruby_version] = RUBY_VERSION
      results[:platform] = RUBY_PLATFORM

      emit(results)
      results
    end
  end

  private

  def generate_class_files(dir)
    CLASS_COUNT.times do |i|
      File.write(File.join(dir, "matrix_class_#{i}.rb"), class_source(i))
    end
  end

  def class_source(i)
    name = "MatrixClass#{i}"
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
      require File.join(dir, "matrix_class_#{i}")
    end
  end

  def measure_matrix
    extractor = Datadog::SymbolDatabase::Extractor.new(
      logger: Logger.new(File::NULL),
      settings: StubSettings.new,
    )

    # Warmup the JIT/inline caches so the first measured arm doesn't pay
    # cold-start costs the later arms have already amortized.
    warmup_duration = VALIDATE_BENCHMARK_MODE ? 0.01 : 1.0
    run_arm(75, warmup_duration, extractor: nil)
    gc_settle

    arms = {}
    BASELINES.each do |baseline_pct|
      no_extractor = run_arm(baseline_pct, WINDOW_SECONDS, extractor: nil)
      gc_settle
      with_extractor = run_arm(baseline_pct, WINDOW_SECONDS, extractor: extractor)
      gc_settle

      base_ops = no_extractor[:ops_per_sec].to_f
      rps_drop = (base_ops > 0) ? 1.0 - (with_extractor[:ops_per_sec].to_f / base_ops) : nil

      arms[baseline_pct] = {
        no_extractor: no_extractor,
        with_extractor: with_extractor,
        rps_drop: rps_drop,
      }
    end
    arms
  end

  # One measurement arm. Workload runs cpu_chunk (a fixed amount of pure
  # CPU work) followed by a sleep sized so that work / (work + sleep) =
  # baseline_pct/100. If extractor is given, a bg thread loops on
  # extract_all for the entire arm window. Returns ops/sec + percentile
  # latency stats.
  def run_arm(baseline_pct, duration_seconds, extractor:)
    sleep_seconds = if baseline_pct >= 100
      0.0
    else
      @cpu_chunk_seconds * (100 - baseline_pct) / baseline_pct.to_f
    end

    bg = nil
    stop_bg = false
    if extractor
      bg = Thread.new do
        # extract_all until the main thread signals stop. Any exception
        # propagates out via bg.join below — Thread#join re-raises in the
        # caller when the thread terminated with an exception.
        loop do
          break if stop_bg
          extractor.extract_all
        end
      end
    end

    samples_ns = []
    wall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    deadline_ns = (wall_start * 1e9).to_i + (duration_seconds * 1e9).to_i

    loop do
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      cpu_chunk
      sleep(sleep_seconds) if sleep_seconds > 0
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      samples_ns << (t1 - t0)
      break if t1 >= deadline_ns
    end
    wall_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    if bg
      stop_bg = true
      # Cap how long we wait for the bg thread to finish its current
      # extract_all. With the throttle (sleep every N modules), one iteration
      # can take seconds on a process with many loaded modules — the
      # measurement window is already complete here, so abandon a still-running
      # iteration rather than block the run. Without this cap, validate-mode
      # runs (10 arms × bg.join across the matrix) can blow past
      # expect_in_fork's 10s timeout on slower CI Rubies.
      unless bg.join(VALIDATE_BENCHMARK_MODE ? 0.05 : 0.5)
        bg.kill
        bg.join
      end
    end

    wall_seconds = wall_end - wall_start
    {
      ops: samples_ns.size,
      wall_seconds: wall_seconds,
      ops_per_sec: (wall_seconds > 0) ? samples_ns.size / wall_seconds : 0.0,
    }.merge(percentile_stats(samples_ns))
  end

  # Time one cpu_chunk call. Warm up first so JIT/inline caches don't
  # inflate the calibration sample. Take the median of 5 samples to
  # de-noise scheduler interference.
  #
  # Validate mode skips this — the bitrot check only needs the code path
  # to run, not a real-host CPU calibration. 8 cpu_chunks at ~73ms each
  # were the largest fixed cost on CI (~580ms) before this short-circuit.
  def calibrate_cpu_chunk
    return 0.01 if VALIDATE_BENCHMARK_MODE

    3.times { cpu_chunk }
    samples = Array.new(5) do
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cpu_chunk
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    end
    samples.sort[samples.size / 2]
  end

  # Force three GC passes between arms in real mode so each arm starts from
  # a comparable heap state. Validate mode skips this — the bitrot check
  # doesn't measure anything, and the 8× GC.start blocks were 4-6s of CI
  # wall time with high run-to-run variance (the entire source of the
  # observed 6.4s ↔ 8.7s spread).
  def gc_settle
    return if VALIDATE_BENCHMARK_MODE

    3.times { GC.start }
  end

  # A fixed amount of pure-Ruby CPU work. ~10 ms on a modern host; exact
  # wall duration is measured by calibrate_cpu_chunk so sleep_seconds in
  # run_arm scales the baseline correctly per host.
  def cpu_chunk
    acc = 0xdead
    10_000.times do
      100.times do
        acc = ((acc * 1_103_515_245) + 12_345) & 0x7fff_ffff
      end
    end
    acc
  end

  def percentile_stats(samples_ns)
    return {mean_ns: 0, p50_ns: 0, p90_ns: 0, p99_ns: 0, max_ns: 0} if samples_ns.empty?

    sorted = samples_ns.sort
    n = sorted.size
    {
      mean_ns: sorted.sum.to_f / n,
      p50_ns: sorted[n / 2],
      p90_ns: sorted[(n * 0.90).to_i],
      p99_ns: sorted[(n * 0.99).to_i],
      max_ns: sorted[-1],
    }
  end

  def emit(results)
    json = JSON.pretty_generate(results)
    puts json

    return if VALIDATE_BENCHMARK_MODE

    File.write("#{File.basename(__FILE__, '.rb')}-results.json", json)
  end
end

puts "Current pid is #{Process.pid}"

SymbolDatabaseBaselineMatrixBenchmark.new.run
