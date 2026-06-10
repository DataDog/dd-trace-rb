#
# "Instrumentation" part of Dynamic Instrumentation benchmarks.
#
# Each instrumented configuration is measured with two probe rate-limit
# settings to decompose the wrapper's per-call cost:
#
#   rate_limit=1_000_000  - benchmark runs below the bucket ceiling, every
#                           probe invocation fires the full path (firing).
#   rate_limit=1          - one token initially + 1/sec refill. At the
#                           benchmark's call rate, ~99.999% of invocations
#                           hit the rate-limited skip branch (skip).
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
# Typical result:
#
# Comparison:
#                          method instrumentation - cleared:   556227.8 i/s
#                            line instrumentation - cleared:   553976.4 i/s - same-ish: difference falls within error
#                                        no instrumentation:   544419.0 i/s - same-ish: difference falls within error
#                                no instrumentation - again:   499320.2 i/s - same-ish: difference falls within error
#              method instrumentation - rate_limit=1 (skip):   295040.9 i/s - 1.89x  slower
#     line instrumentation - targeted - rate_limit=1 (skip):   279164.6 i/s - 1.99x  slower
#           method instrumentation - rate_limit=1M (firing):   122105.7 i/s - 4.56x  slower
#  line instrumentation - targeted - rate_limit=1M (firing):   108801.5 i/s - 5.11x  slower
#   line instrumentation - untargeted - rate_limit=1 (skip):    60316.8 i/s - 9.22x  slower
# line instrumentation - untargeted - rate_limit=1M (firing):    44622.4 i/s - 12.47x  slower
#
# Per-call wrapper overhead, computed as (1/instr_ips) - (1/baseline_ips)
# from the numbers above:
#
#                                       skip path     firing path
#   method probe                        ~1.55 us      ~6.35 us
#   line probe - targeted               ~1.75 us      ~7.35 us
#   line probe - untargeted             ~14.7 us      ~20.6 us
#
# Method-probe firing is ~4x more expensive per call than skip. In
# production, where the probe rate limit caps firing at 5000/sec per probe
# and the customer method runs at whatever the application produces, the
# skip number is the per-call cost a customer pays on the overwhelming
# majority of probed-method invocations.
#
# Targeted line instrumentation has similar per-call cost to method
# instrumentation in both firing and skip variants.
#
# Untargeted line instrumentation is much slower than targeted because the
# TracePoint fires for every line in the file rather than only the
# instrumented line. The skip variant is still slow (~14.7 us) because the
# per-line TracePoint callback runs even when the rate limiter rejects
# snapshot delivery. Untargeted line probes remain unsuitable for
# production use; the skip-variant measurement is the floor cost that even
# rate-limit-skipped traffic pays.
#
# After instrumentation is removed, performance returns to baseline within
# measurement error: method-cleared was 2.6% below baseline, line-cleared was
# 1.1% above baseline, no-instr-again was 0.8% above baseline -- all within the
# +/- 1.6-2.2% error bands. A prior version of this header documented a 6-10%
# residual loss with two candidate causes (lingering code overhead vs. CPU
# thermal throttling); the throttling theory is consistent with what we see
# now -- with turbo disabled the residual loss disappears.
#
# To reproduce stable measurements on a laptop, run as root:
#   echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
# then run the benchmark pinned to one P-core's SMT pair:
#   taskset -c 2,3 bundle exec ruby benchmarks/di_instrument.rb
# Without these, the default intel_pstate powersave governor swings P-core
# frequency between 400 MHz and ~4.3 GHz under load, producing +/- 16-36%
# per-report error bands that swamp the differences this benchmark measures.
#

# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'datadog'
# Need to require datadog/di explicitly because dynamic instrumentation is not
# currently integrated into the Ruby tracer due to being under development.
require 'datadog/di'
require 'datadog/di/proc_responder'

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

  attr_reader :instrumenter

  def logger
    @logger ||= Logger.new($stderr)
  end

  def configure
    settings = Datadog.configuration
    yield settings if block_given?

    redactor = Datadog::DI::Redactor.new(settings)
    serializer = Datadog::DI::Serializer.new(settings, redactor)
    @instrumenter = Datadog::DI::Instrumenter.new(settings, serializer, logger,
      code_tracker: Datadog::DI.code_tracker)
  end

  def run_benchmark
    configure

    m = Target.instance_method(:test_method_for_line_probe)
    file, line = m.source_location

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report('no instrumentation') do
        Target.new.test_method
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    # Method instrumentation is run twice with deliberately extreme rate
    # limits to decompose the wrapper's per-call cost:
    #
    #   rate_limit=1_000_000  - benchmark runs below the token-bucket
    #                           ceiling, every call fires the full snapshot
    #                           path. Measures firing-path cost.
    #   rate_limit=1          - one token initially + one refill per second.
    #                           At ~100k calls/sec, ~99.999% of calls hit
    #                           the rate-limited skip branch. Measures
    #                           skip-path cost (the dominant production
    #                           overhead, since real workloads vastly exceed
    #                           any per-probe rate limit).
    #
    # Note: this benchmark does not set capture_snapshot, so the firing
    # variant exercises Context construction + responder dispatch but not
    # serialize_args. For probes with capture_snapshot=true the firing-path
    # cost is higher than what is measured here.

    calls = 0
    executed_proc = lambda do |context|
      calls += 1
    end

    probe = Datadog::DI::Probe.new(id: 1, type: :log,
      type_name: 'DIInstrumentBenchmark::Target', method_name: 'test_method',
      rate_limit: 1_000_000,)
    responder = Datadog::DI::ProcResponder.new(executed_proc)
    rv = instrumenter.hook_method(probe, responder)
    unless rv
      raise "Method probe was not successfully installed (rate_limit=1M)"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report('method instrumentation - rate_limit=1M (firing)') do
        Target.new.test_method
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Method instrumentation (rate_limit=1M) did not work - callback was never invoked"
    end

    if calls < 1000 && !VALIDATE_BENCHMARK_MODE
      raise "Method instrumentation (rate_limit=1M): expected at least 1000 firing calls, got #{calls}"
    end

    instrumenter.unhook(probe)

    calls = 0
    probe = Datadog::DI::Probe.new(id: 1, type: :log,
      type_name: 'DIInstrumentBenchmark::Target', method_name: 'test_method',
      rate_limit: 1,)
    responder = Datadog::DI::ProcResponder.new(executed_proc)
    rv = instrumenter.hook_method(probe, responder)
    unless rv
      raise "Method probe was not successfully installed (rate_limit=1)"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report('method instrumentation - rate_limit=1 (skip)') do
        Target.new.test_method
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Method instrumentation (rate_limit=1) did not work - callback was never invoked"
    end

    # rate_limit=1 with ~12s of total time (2s warmup + 10s measure) should
    # produce ~12 firing calls. Anything over 100 indicates the rate limiter
    # is not enforcing.
    if calls > 100 && !VALIDATE_BENCHMARK_MODE
      raise "Method instrumentation (rate_limit=1): rate limit not enforced, got #{calls} firing calls"
    end

    instrumenter.unhook(probe)

    # We benchmark untargeted and targeted trace points; untargeted ones
    # are prohibited by default, permit them.
    # In order to install untargeted trace point, we currently need to
    # disable code tracking.
    Datadog::DI.deactivate_tracking!
    configure do |c|
      c.dynamic_instrumentation.internal.untargeted_trace_points = true
    end

    calls = 0
    probe = Datadog::DI::Probe.new(id: 1, type: :log,
      file: file, line_no: line + 1, rate_limit: 1_000_000,)
    responder = Datadog::DI::ProcResponder.new(executed_proc)
    rv = instrumenter.hook_line(probe, responder)
    unless rv
      raise "Line probe (untargeted, rate_limit=1M) was not successfully installed"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )
      x.report('line instrumentation - untargeted - rate_limit=1M (firing)') do
        Target.new.test_method_for_line_probe
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Line instrumentation (untargeted, rate_limit=1M) did not work - callback was never invoked"
    end

    if calls < 1000 && !VALIDATE_BENCHMARK_MODE
      raise "Line instrumentation (untargeted, rate_limit=1M): expected at least 1000 firing calls, got #{calls}"
    end

    instrumenter.unhook(probe)

    calls = 0
    probe = Datadog::DI::Probe.new(id: 1, type: :log,
      file: file, line_no: line + 1, rate_limit: 1,)
    responder = Datadog::DI::ProcResponder.new(executed_proc)
    rv = instrumenter.hook_line(probe, responder)
    unless rv
      raise "Line probe (untargeted, rate_limit=1) was not successfully installed"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )
      x.report('line instrumentation - untargeted - rate_limit=1 (skip)') do
        Target.new.test_method_for_line_probe
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Line instrumentation (untargeted, rate_limit=1) did not work - callback was never invoked"
    end

    if calls > 100 && !VALIDATE_BENCHMARK_MODE
      raise "Line instrumentation (untargeted, rate_limit=1): rate limit not enforced, got #{calls} firing calls"
    end

    instrumenter.unhook(probe)

    Datadog::DI.activate_tracking!
    configure do |c|
      c.dynamic_instrumentation.internal.untargeted_trace_points = false
    end

    if defined?(DITarget)
      raise "DITarget is already defined, this should not happen"
    end
    require_relative 'support/di_target'
    unless defined?(DITarget)
      raise "DITarget is not defined, this should not happen"
    end

    m = DITarget.instance_method(:test_method_for_line_probe)
    targeted_file, targeted_line = m.source_location

    calls = 0
    probe = Datadog::DI::Probe.new(id: 1, type: :log,
      file: targeted_file, line_no: targeted_line + 1, rate_limit: 1_000_000,)
    responder = Datadog::DI::ProcResponder.new(executed_proc)
    rv = instrumenter.hook_line(probe, responder)
    unless rv
      raise "Line probe (targeted, rate_limit=1M) was not successfully installed"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report('line instrumentation - targeted - rate_limit=1M (firing)') do
        DITarget.new.test_method_for_line_probe
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Targeted line instrumentation (rate_limit=1M) did not work - callback was never invoked"
    end

    if calls < 1000 && !VALIDATE_BENCHMARK_MODE
      raise "Targeted line instrumentation (rate_limit=1M): expected at least 1000 firing calls, got #{calls}"
    end

    instrumenter.unhook(probe)

    calls = 0
    probe = Datadog::DI::Probe.new(id: 1, type: :log,
      file: targeted_file, line_no: targeted_line + 1, rate_limit: 1,)
    responder = Datadog::DI::ProcResponder.new(executed_proc)
    rv = instrumenter.hook_line(probe, responder)
    unless rv
      raise "Line probe (targeted, rate_limit=1) was not successfully installed"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report('line instrumentation - targeted - rate_limit=1 (skip)') do
        DITarget.new.test_method_for_line_probe
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Targeted line instrumentation (rate_limit=1) did not work - callback was never invoked"
    end

    if calls > 100 && !VALIDATE_BENCHMARK_MODE
      raise "Targeted line instrumentation (rate_limit=1): rate limit not enforced, got #{calls} firing calls"
    end

    # Now, remove all installed hooks and check that the performance of
    # target code is approximately what it was prior to hook installation.

    instrumenter.unhook(probe)

    calls = 0

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      # This benchmark should produce identical results to the
      # "no instrumentation" benchmark.
      x.report('method instrumentation - cleared') do
        Target.new.test_method
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls != 0
      raise "Method instrumentation was not cleared (#{calls} calls recorded)"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      # This benchmark should produce identical results to the
      # "no instrumentation" benchmark.
      x.report('line instrumentation - cleared') do
        Target.new.test_method_for_line_probe
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls != 0
      raise "Line instrumentation was not cleared (#{calls} calls recorded)"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report('no instrumentation - again') do
        Target.new.not_instrumented
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

DIInstrumentBenchmark.new.instance_exec do
  run_benchmark
end
