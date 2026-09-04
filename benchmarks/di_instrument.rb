#
# "Instrumentation" part of Dynamic Instrumentation benchmarks.
#
# Each instrumented configuration is measured with three variants that
# decompose the wrapper's per-call cost. All use a benchmark-only global
# limiter (see BenchInstrumenter/ToggleLimiter) whose admission the
# benchmark controls, so each variant isolates one branch of the per-call
# path:
#
#   rate_limit=1M, global admit   - per-probe and global limiter both admit,
#                                   so every call fires the full path
#                                   (firing).
#   rate_limit=1M, global reject  - per-probe admits, global limiter rejects,
#                                   so every call takes the global-rate-limit
#                                   skip branch (global reject).
#   rate_limit=1                  - one token initially + 1/sec refill, so
#                                   ~99.999% of calls hit the per-probe skip
#                                   branch before the global limiter is
#                                   consulted (skip).
#
# The skip-path number is the dominant production overhead, since real
# workloads vastly exceed any per-probe rate limit. The firing-path number
# is what each delivered snapshot costs.
#
# capture_snapshot is not set on the probes (defaults to false), so the
# firing path measured here exercises Context construction and responder
# dispatch but not serialize_args. For probes with capture_snapshot=true,
# the firing-path cost is higher than what this benchmark reports.
#
# Typical result (local run, Ruby 3.2.3, x86_64-linux-gnu):
#
# Comparison:
#                                               no instrumentation:   615759.9 i/s
#                                 method instrumentation - cleared:   586395.9 i/s - same-ish: difference falls within error
#                                       no instrumentation - again:   582805.3 i/s - same-ish: difference falls within error
#                                   line instrumentation - cleared:   557115.8 i/s - same-ish: difference falls within error
#            line instrumentation - targeted - rate_limit=1 (skip):   281647.2 i/s - 2.19x  slower
#                     method instrumentation - rate_limit=1 (skip):   279444.7 i/s - 2.20x  slower
#           method instrumentation - rate_limit=1M (global reject):   229992.0 i/s - 2.68x  slower
#  line instrumentation - targeted - rate_limit=1M (global reject):   213673.2 i/s - 2.88x  slower
#         line instrumentation - targeted - rate_limit=1M (firing):   118301.0 i/s - 5.21x  slower
#                  method instrumentation - rate_limit=1M (firing):   112104.9 i/s - 5.49x  slower
#          line instrumentation - untargeted - rate_limit=1 (skip):    96671.7 i/s - 6.37x  slower
# line instrumentation - untargeted - rate_limit=1M (global reject):    82990.0 i/s - 7.42x  slower
#       line instrumentation - untargeted - rate_limit=1M (firing):    61094.8 i/s - 10.08x  slower
#
# Per-call wrapper overhead, computed as (1/instr_ips) - (1/baseline_ips)
# from the numbers above:
#
#                                       skip path     global reject     firing path
#   method probe                        ~1.95 us      ~2.72 us          ~7.30 us
#   line probe - targeted               ~1.93 us      ~3.06 us          ~6.83 us
#   line probe - untargeted             ~8.72 us      ~10.43 us         ~14.74 us
#
# Method-probe firing is ~4x more expensive per call than skip. In
# production, where the probe rate limit caps firing at 5000/sec per probe
# and the customer method runs at whatever the application produces, the
# skip number is the per-call cost a customer pays on the overwhelming
# majority of probed-method invocations.
#
# The global-reject variant (per-probe limiter admits, process-wide global
# limiter rejects) costs more than skip but less than firing, because the
# wrapper performs the per-probe admission work and the global-limiter
# consultation before taking the skip branch.
#
# Targeted line instrumentation has similar per-call cost to method
# instrumentation across all three variants.
#
# Untargeted line instrumentation is much slower than targeted because the
# TracePoint fires for every line in the file rather than only the
# instrumented line. The skip variant is still slow (~8.7 us) because the
# per-line TracePoint callback runs even when the rate limiter rejects
# snapshot delivery. Untargeted line probes remain unsuitable for
# production use; the skip-variant measurement is the floor cost that even
# rate-limit-skipped traffic pays.
#

# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV["VALIDATE_BENCHMARK"] == "true"

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require "benchmark/ips"
require "datadog"
# Need to require datadog/di explicitly because dynamic instrumentation is not
# currently integrated into the Ruby tracer due to being under development.
require "datadog/di"
require "datadog/di/logger"
require "datadog/di/proc_responder"

class DIInstrumentBenchmark
  class Target
    def test_method
      # Perform some work to take up time
      SecureRandom.uuid
    end

    def not_instrumented
      SecureRandom.uuid
    end

    # This method must have an executable line as its first line,
    # otherwise line instrumentation won't work.
    # The code in this method should be identical to test_method above.
    # The two methods are separate so that instrumentation targets are
    # different, to avoid a false positive if line instrumemntation fails
    # to work and method instrumentation isn't cleared and continues to
    # invoke the callback.
    def test_method_for_line_probe
      SecureRandom.uuid
    end
  end

  # The process-wide global rate limiters are orthogonal admission control
  # and must not pollute per-call wrapper-cost measurement. BenchInstrumenter
  # overrides the public probe_global_rate_limiter seam to return a limiter
  # whose admission the benchmark toggles, so a single instrumenter isolates
  # the firing branch (admit) and the global-reject branch (reject).
  # Production wiring is unchanged; these are benchmark-only.
  module ToggleLimiter
    class << self
      attr_accessor :admit
      # Count of allow? consultations, used by the global-reject variants to
      # self-check that the wrapper actually reached the global limiter
      # (calls == 0 alone cannot prove the wrapper ran, since calls is
      # expected to stay 0 when the limiter rejects).
      attr_accessor :consulted
      def allow?(*)
        self.consulted += 1
        admit
      end
    end
    self.admit = true
    self.consulted = 0
  end

  class BenchInstrumenter < Datadog::DI::Instrumenter
    def probe_global_rate_limiter(*)
      ToggleLimiter
    end
  end

  attr_reader :instrumenter

  def logger
    @logger ||= Logger.new($stderr)
  end

  def configure
    settings = Datadog.configuration
    yield settings if block_given?

    redactor = Datadog::DI::Redactor.new(settings)
    serializer = Datadog::DI::Serializer.new(settings, redactor)
    # Wrap in the DI::Logger facade (as lib/datadog/di/component.rb does)
    # so the instrumenter's logger.trace calls on the global-rate-limit
    # skip path resolve; stdlib Logger has no trace method.
    di_logger = Datadog::DI::Logger.new(settings, logger)
    @instrumenter = BenchInstrumenter.new(settings, serializer, di_logger,
      code_tracker: Datadog::DI.code_tracker, correlation_sampler: nil)
  end

  # Run one Benchmark.ips measurement for the given report label. The target
  # block is forwarded straight to benchmark-ips (no per-iteration wrapper) so
  # the measured cost is the target code plus instrumentation, not the helper.
  def measure(report:, &target)
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )
      x.report(report, &target)
      x.save! "#{File.basename(__FILE__, ".rb")}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  # Install a probe, measure it, and unhook it. ToggleLimiter.admit is restored
  # to true in an ensure so a raised assertion cannot leak the global-reject
  # state into a later variant.
  def measure_variant(report:, hook:, probe:, &target)
    rv = instrumenter.public_send(hook, probe,
      Datadog::DI::ProcResponder.new(@executed_proc))
    raise "#{report}: probe was not successfully installed" unless rv

    measure(report: report, &target)
    instrumenter.unhook(probe)
  ensure
    ToggleLimiter.admit = true
  end

  def run_benchmark
    configure

    m = Target.instance_method(:test_method_for_line_probe)
    file, line = m.source_location

    measure(report: "no instrumentation") { Target.new.test_method }

    # Shared responder callback. It closes over the local `calls` counter, which
    # each variant resets before its measurement and asserts on after. Sharing
    # one callback also lets the post-unhook "cleared" blocks detect a leaked
    # hook, which would still fire this callback and bump `calls`.
    calls = 0
    @executed_proc = lambda do |context|
      calls += 1
    end

    calls = 0
    measure_variant(
      report: "method instrumentation - rate_limit=1M (firing)",
      hook: :hook_method,
      probe: Datadog::DI::Probe.new(id: 1, type: :log,
        type_name: "DIInstrumentBenchmark::Target", method_name: "test_method",
        rate_limit: 1_000_000,),
    ) { Target.new.test_method }

    if calls < 1
      raise "Method instrumentation (rate_limit=1M) did not work - callback was never invoked"
    end

    if calls < 100_000 && !VALIDATE_BENCHMARK_MODE
      raise "Method instrumentation (rate_limit=1M): expected at least 100_000 firing calls, got #{calls}"
    end

    calls = 0
    measure_variant(
      report: "method instrumentation - rate_limit=1 (skip)",
      hook: :hook_method,
      probe: Datadog::DI::Probe.new(id: 1, type: :log,
        type_name: "DIInstrumentBenchmark::Target", method_name: "test_method",
        rate_limit: 1,),
    ) { Target.new.test_method }

    if calls < 1
      raise "Method instrumentation (rate_limit=1) did not work - callback was never invoked"
    end

    # rate_limit=1 with ~12s of total time (2s warmup + 10s measure) should
    # produce ~12 firing calls. Anything over 100 indicates the rate limiter
    # is not enforcing.
    if calls > 100 && !VALIDATE_BENCHMARK_MODE
      raise "Method instrumentation (rate_limit=1): rate limit not enforced, got #{calls} firing calls"
    end

    calls = 0
    ToggleLimiter.admit = false
    ToggleLimiter.consulted = 0
    measure_variant(
      report: "method instrumentation - rate_limit=1M (global reject)",
      hook: :hook_method,
      probe: Datadog::DI::Probe.new(id: 1, type: :log,
        type_name: "DIInstrumentBenchmark::Target", method_name: "test_method",
        rate_limit: 1_000_000,),
    ) { Target.new.test_method }

    if calls != 0
      raise "Method instrumentation (rate_limit=1M, global reject): expected 0 firing calls, got #{calls}"
    end

    if ToggleLimiter.consulted < 100_000 && !VALIDATE_BENCHMARK_MODE
      raise "Method instrumentation (rate_limit=1M, global reject): wrapper did not reach the global limiter, only #{ToggleLimiter.consulted} consultations"
    end

    # We benchmark untargeted and targeted trace points; untargeted ones
    # are prohibited by default, permit them.
    # In order to install untargeted trace point, we currently need to
    # disable code tracking.
    Datadog::DI.deactivate_tracking!
    configure do |c|
      c.dynamic_instrumentation.internal.untargeted_trace_points = true
    end

    calls = 0
    measure_variant(
      report: "line instrumentation - untargeted - rate_limit=1M (firing)",
      hook: :hook_line,
      probe: Datadog::DI::Probe.new(id: 1, type: :log,
        file: file, line_no: line + 1, rate_limit: 1_000_000,),
    ) { Target.new.test_method_for_line_probe }

    if calls < 1
      raise "Line instrumentation (untargeted, rate_limit=1M) did not work - callback was never invoked"
    end

    if calls < 100_000 && !VALIDATE_BENCHMARK_MODE
      raise "Line instrumentation (untargeted, rate_limit=1M): expected at least 100_000 firing calls, got #{calls}"
    end

    calls = 0
    measure_variant(
      report: "line instrumentation - untargeted - rate_limit=1 (skip)",
      hook: :hook_line,
      probe: Datadog::DI::Probe.new(id: 1, type: :log,
        file: file, line_no: line + 1, rate_limit: 1,),
    ) { Target.new.test_method_for_line_probe }

    if calls < 1
      raise "Line instrumentation (untargeted, rate_limit=1) did not work - callback was never invoked"
    end

    if calls > 100 && !VALIDATE_BENCHMARK_MODE
      raise "Line instrumentation (untargeted, rate_limit=1): rate limit not enforced, got #{calls} firing calls"
    end

    calls = 0
    ToggleLimiter.admit = false
    ToggleLimiter.consulted = 0
    measure_variant(
      report: "line instrumentation - untargeted - rate_limit=1M (global reject)",
      hook: :hook_line,
      probe: Datadog::DI::Probe.new(id: 1, type: :log,
        file: file, line_no: line + 1, rate_limit: 1_000_000,),
    ) { Target.new.test_method_for_line_probe }

    if calls != 0
      raise "Line instrumentation (untargeted, rate_limit=1M, global reject): expected 0 firing calls, got #{calls}"
    end

    if ToggleLimiter.consulted < 100_000 && !VALIDATE_BENCHMARK_MODE
      raise "Line instrumentation (untargeted, rate_limit=1M, global reject): wrapper did not reach the global limiter, only #{ToggleLimiter.consulted} consultations"
    end

    Datadog::DI.activate_tracking!
    configure do |c|
      c.dynamic_instrumentation.internal.untargeted_trace_points = false
    end

    if defined?(DITarget)
      raise "DITarget is already defined, this should not happen"
    end
    require_relative "support/di_target"
    unless defined?(DITarget)
      raise "DITarget is not defined, this should not happen"
    end

    m = DITarget.instance_method(:test_method_for_line_probe)
    targeted_file, targeted_line = m.source_location

    calls = 0
    measure_variant(
      report: "line instrumentation - targeted - rate_limit=1M (firing)",
      hook: :hook_line,
      probe: Datadog::DI::Probe.new(id: 1, type: :log,
        file: targeted_file, line_no: targeted_line + 1, rate_limit: 1_000_000,),
    ) { DITarget.new.test_method_for_line_probe }

    if calls < 1
      raise "Targeted line instrumentation (rate_limit=1M) did not work - callback was never invoked"
    end

    if calls < 100_000 && !VALIDATE_BENCHMARK_MODE
      raise "Targeted line instrumentation (rate_limit=1M): expected at least 100_000 firing calls, got #{calls}"
    end

    calls = 0
    measure_variant(
      report: "line instrumentation - targeted - rate_limit=1 (skip)",
      hook: :hook_line,
      probe: Datadog::DI::Probe.new(id: 1, type: :log,
        file: targeted_file, line_no: targeted_line + 1, rate_limit: 1,),
    ) { DITarget.new.test_method_for_line_probe }

    if calls < 1
      raise "Targeted line instrumentation (rate_limit=1) did not work - callback was never invoked"
    end

    if calls > 100 && !VALIDATE_BENCHMARK_MODE
      raise "Targeted line instrumentation (rate_limit=1): rate limit not enforced, got #{calls} firing calls"
    end

    calls = 0
    ToggleLimiter.admit = false
    ToggleLimiter.consulted = 0
    measure_variant(
      report: "line instrumentation - targeted - rate_limit=1M (global reject)",
      hook: :hook_line,
      probe: Datadog::DI::Probe.new(id: 1, type: :log,
        file: targeted_file, line_no: targeted_line + 1, rate_limit: 1_000_000,),
    ) { DITarget.new.test_method_for_line_probe }

    if calls != 0
      raise "Targeted line instrumentation (rate_limit=1M, global reject): expected 0 firing calls, got #{calls}"
    end

    if ToggleLimiter.consulted < 100_000 && !VALIDATE_BENCHMARK_MODE
      raise "Targeted line instrumentation (rate_limit=1M, global reject): wrapper did not reach the global limiter, only #{ToggleLimiter.consulted} consultations"
    end

    # Now, remove all installed hooks and check that the performance of
    # target code is approximately what it was prior to hook installation.

    calls = 0
    measure(report: "method instrumentation - cleared") { Target.new.test_method }

    if calls != 0
      raise "Method instrumentation was not cleared (#{calls} calls recorded)"
    end

    calls = 0
    measure(report: "line instrumentation - cleared") { Target.new.test_method_for_line_probe }

    if calls != 0
      raise "Line instrumentation was not cleared (#{calls} calls recorded)"
    end

    measure(report: "no instrumentation - again") { Target.new.not_instrumented }
  end
end

puts "Current pid is #{Process.pid}"

DIInstrumentBenchmark.new.instance_exec do
  run_benchmark
end
