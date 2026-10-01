# Symbol Database background-impact benchmark.
#
# Measures how SymDB extraction running on a background thread impacts a
# concurrent main-thread workload. Surfaces GVL contention as a p99 latency
# ratio between two arms:
#
#   baseline_pre   — main-thread workload alone, no extraction running
#   treatment      — same workload while a background thread runs Extractor#extract_all
#   baseline_post  — workload alone again, to detect order effects (GC state,
#                    warm caches, etc.) that would bias the comparison
#
# Reported statistic: p99_ratio = treatment_p99 / baseline_pre_p99.
# A ratio near 1.0 means extraction is non-blocking from the main thread's
# perspective; a large ratio means extraction substantially delays the main
# thread.

VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'fileutils'
require 'json'
require 'logger'
require 'tmpdir'

require 'datadog/symbol_database/extractor'

class SymbolDatabaseBackgroundImpactBenchmark
  CLASS_COUNT = VALIDATE_BENCHMARK_MODE ? 10 : 2500

  # Main-thread workload iteration count per arm. Tuned so each arm runs
  # several seconds in real mode — longer than extraction wall time on 2500
  # classes — so the treatment arm has samples both during and after the
  # extraction window.
  WORKLOAD_ITERATIONS = VALIDATE_BENCHMARK_MODE ? 200 : 1_000_000

  # Warmup iteration count run before the first measured arm.
  WARMUP_ITERATIONS = VALIDATE_BENCHMARK_MODE ? 100 : 500_000

  # Minimum fraction of treatment-arm samples that must fall inside the
  # extraction window for the benchmark to be valid. Below this we cannot
  # claim to have measured the in-extraction p99 with any confidence.
  MIN_OVERLAP_FRACTION = VALIDATE_BENCHMARK_MODE ? 0.0 : 0.10

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

      results = measure
      results[:class_count] = CLASS_COUNT
      results[:workload_iterations] = WORKLOAD_ITERATIONS
      results[:warmup_iterations] = WARMUP_ITERATIONS
      results[:ruby_version] = RUBY_VERSION
      results[:platform] = RUBY_PLATFORM

      emit(results)
      enforce_requirement(results)
      results
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

  def measure
    extractor = Datadog::SymbolDatabase::Extractor.new(
      logger: Logger.new(File::NULL),
      settings: StubSettings.new
    )

    WARMUP_ITERATIONS.times { |i| workload_op(i) }

    3.times { GC.start }

    baseline_pre = time_workload_arm(WORKLOAD_ITERATIONS)

    3.times { GC.start }

    treatment = time_workload_with_extraction(WORKLOAD_ITERATIONS, extractor)

    3.times { GC.start }

    baseline_post = time_workload_arm(WORKLOAD_ITERATIONS)

    {
      baseline_pre: baseline_pre,
      treatment: treatment,
      baseline_post: baseline_post,
      summary: build_summary(baseline_pre, treatment, baseline_post),
    }
  end

  # Run the workload N times with no background activity. Returns the arm stats.
  def time_workload_arm(iterations)
    samples_ns = Array.new(iterations)
    gc_count_before = GC.count

    wall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times do |i|
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      workload_op(i)
      samples_ns[i] = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - t0
    end
    wall_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    stats_for(samples_ns, wall_end - wall_start, GC.count - gc_count_before)
  end

  # Run the workload while a background thread runs extract_all. Captures
  # per-sample timestamps and filters them to those that fell during the
  # extraction window so the treatment stat reflects in-extraction behavior.
  def time_workload_with_extraction(iterations, extractor)
    samples_ns = Array.new(iterations)
    sample_starts_ns = Array.new(iterations)
    gc_count_before = GC.count

    extraction_started_q = Queue.new
    extraction_start_ns = nil
    extraction_end_ns = nil
    file_scope_count = nil

    bg = Thread.new do
      extraction_started_q << true
      extraction_start_ns = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      scopes = extractor.extract_all
      extraction_end_ns = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      file_scope_count = scopes.size
    end

    # Wait for the extraction thread to be scheduled before starting the
    # workload. The Queue handshake guarantees the thread is running; the
    # nanosecond timestamp captured inside the thread marks the actual start
    # of extraction work.
    extraction_started_q.pop

    wall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times do |i|
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      workload_op(i)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      sample_starts_ns[i] = t0
      samples_ns[i] = t1 - t0
    end
    wall_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Thread#value joins and re-raises any exception from the bg block. If
    # extract_all blew up silently we want CI to see it, not produce a
    # baseline-shaped treatment arm that looks like "no regression".
    bg.value

    # If the workload finished before extraction did, that's expected and
    # fine — all samples count. If extraction finished before the workload
    # did, filter out post-extraction samples for the treatment stat.
    overlap_samples_ns = []
    samples_ns.each_with_index do |duration, i|
      sample_start = sample_starts_ns[i]
      next if sample_start.nil?
      if sample_start >= extraction_start_ns && sample_start <= extraction_end_ns
        overlap_samples_ns << duration
      end
    end

    overlap_fraction = overlap_samples_ns.size.to_f / iterations
    extraction_wall_seconds = (extraction_end_ns - extraction_start_ns) / 1e9

    overall = stats_for(samples_ns, wall_end - wall_start, GC.count - gc_count_before)

    arm = overall.merge(
      extraction_wall_seconds: extraction_wall_seconds,
      file_scope_count: file_scope_count,
      overlap_sample_count: overlap_samples_ns.size,
      overlap_fraction: overlap_fraction,
    )

    if overlap_samples_ns.size >= 2
      arm[:in_window] = percentile_stats(overlap_samples_ns)
    end

    if overlap_fraction < MIN_OVERLAP_FRACTION
      arm[:warning] =
        "overlap_fraction #{'%.3f' % overlap_fraction} below MIN_OVERLAP_FRACTION " \
        "#{MIN_OVERLAP_FRACTION} — extraction completed before enough workload " \
        "samples were captured; in-window p99 is not statistically meaningful"
    end

    arm
  end

  # Non-allocating arithmetic workload. Deterministic per i so JIT and
  # inline caches behave identically across arms. Pure integer ops produce
  # no garbage, so GC frequency doesn't drift between arms and the p99
  # comparison reflects GVL contention from extraction rather than GC
  # variability. Sized to ~1-5 μs per call so per-sample clock_gettime
  # overhead (~50 ns) is negligible.
  def workload_op(i)
    acc = i
    200.times do
      acc = ((acc * 1_103_515_245) + 12_345) & 0x7fff_ffff
    end
    acc
  end

  def stats_for(samples_ns, wall_seconds, gc_count_delta)
    percentile_stats(samples_ns).merge(
      ops: samples_ns.size,
      wall_seconds: wall_seconds,
      ops_per_sec: (wall_seconds > 0) ? samples_ns.size / wall_seconds : 0.0,
      gc_count_delta: gc_count_delta,
    )
  end

  def percentile_stats(samples_ns)
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

  def build_summary(baseline_pre, treatment, baseline_post)
    base_p99 = baseline_pre[:p99_ns].to_f
    base_mean = baseline_pre[:mean_ns].to_f
    base_ops = baseline_pre[:ops_per_sec].to_f
    in_window = treatment[:in_window]

    summary = {
      p99_ratio_treatment_over_baseline: (base_p99 > 0) ? treatment[:p99_ns] / base_p99 : nil,
      mean_ratio_treatment_over_baseline: (base_mean > 0) ? treatment[:mean_ns] / base_mean : nil,
      throughput_ratio_treatment_over_baseline: (treatment[:ops_per_sec] > 0 && base_ops > 0) ? treatment[:ops_per_sec] / base_ops : nil,
      order_effect_p99_ratio_post_over_pre: (base_p99 > 0) ? baseline_post[:p99_ns] / base_p99 : nil,
    }

    if in_window
      summary[:p99_ratio_in_window_over_baseline] =
        (base_p99 > 0) ? in_window[:p99_ns] / base_p99 : nil
      summary[:mean_ratio_in_window_over_baseline] =
        (base_mean > 0) ? in_window[:mean_ns] / base_mean : nil
    end

    summary
  end

  def emit(results)
    json = JSON.pretty_generate(results)
    puts json

    return if VALIDATE_BENCHMARK_MODE

    File.write("#{File.basename(__FILE__, '.rb')}-results.json", json)
  end

  # Reference values for acceptable impact on customer applications.
  # A regression that removes the in-extractor throttle
  # would push p99_ratio toward ~2.0 and throughput_ratio toward ~0.7 on a
  # Rails 2,500-class workload (per
  # projects/symdb/reports/extraction-stress-test-2026-05-18.md). In the
  # gitlab microbenchmark environment the synthetic-workload ratios can sit
  # higher than that even with throttle in place because of scheduler and
  # CPU-pinning differences, so this check is informational — it surfaces
  # the warning in CI logs but does not fail the job. Hard regression gating
  # is done by bp-runner via the .gitlab/benchmarks microbenchmarks pipeline
  # comparing ops/sec against master.
  P99_RATIO_THRESHOLD = 1.50
  THROUGHPUT_RATIO_THRESHOLD = 0.80

  def enforce_requirement(results)
    return if VALIDATE_BENCHMARK_MODE # 10-class / 200-iter ratios are too noisy to threshold

    s = results[:summary]
    warnings = []

    p99_ratio = s[:p99_ratio_treatment_over_baseline]
    if p99_ratio && p99_ratio > P99_RATIO_THRESHOLD
      warnings << "p99_ratio_treatment_over_baseline=#{'%.2f' % p99_ratio} exceeds threshold #{P99_RATIO_THRESHOLD}"
    end

    tput_ratio = s[:throughput_ratio_treatment_over_baseline]
    if tput_ratio && tput_ratio < THROUGHPUT_RATIO_THRESHOLD
      warnings << "throughput_ratio_treatment_over_baseline=#{'%.2f' % tput_ratio} below threshold #{THROUGHPUT_RATIO_THRESHOLD}"
    end

    return if warnings.empty?

    warn "Symbol database extraction may be impacting request handling (informational, not a CI gate):"
    warnings.each { |w| warn "  - #{w}" }
  end
end

puts "Current pid is #{Process.pid}"

SymbolDatabaseBackgroundImpactBenchmark.new.run
