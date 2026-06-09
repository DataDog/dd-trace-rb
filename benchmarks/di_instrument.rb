#
# "Instrumentation" part of Dynamic Instrumentation benchmarks.
#
# Typical result (Intel Core Ultra 7 165U, Ruby 3.2.3, intel_pstate/no_turbo=1
# locking P-cores at 1.7 GHz base, taskset -c 2,3 pinning to one P-core):
#
# Comparison:
#       no instrumentation - again:   242268.1 i/s
#   line instrumentation - cleared:   242757.1 i/s - same-ish: within error
#               no instrumentation:   240234.8 i/s - same-ish: within error
# method instrumentation - cleared:   234189.2 i/s - same-ish: within error
#           method instrumentation:   138017.6 i/s - 1.74x  slower
#  line instrumentation - targeted:   117677.4 i/s - 2.04x  slower
# line instrumentation - untargeted:   25021.7 i/s - 9.60x  slower
#
# Per-report error bands were +/- 1.4% to 2.2% on all configurations except
# untargeted line (+/- 5.1%, which is intrinsic to its 40 us/iteration cost
# yielding only ~2,500 iterations per 100 ms benchmark/ips sample).
#
# Targeted line and method instrumentation have similar performance at about
# 50-60% of baseline on this trivial target method. Real-world targets do more
# per call, so the relative overhead of instrumentation will be lower in
# practice than it is in this benchmark.
#
# Untargeted line instrumentation is the slowest configuration by ~4.7x over
# the next-slowest, and remains too slow to be usable.
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
begin
  require 'datadog/di/proc_responder'
rescue LoadError
  # Old tree
end

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

    calls = 0
    probe = Datadog::DI::Probe.new(id: 1, type: :log,
      type_name: 'DIInstrumentBenchmark::Target', method_name: 'test_method')
    executed_proc = lambda do |context|
      calls += 1
    end
    if defined?(Datadog::DI::ProcResponder)
      responder = Datadog::DI::ProcResponder.new(executed_proc)
      rv = instrumenter.hook_method(probe, responder)
    else
      rv = instrumenter.hook_method(probe, &executed_proc)
    end
    unless rv
      raise "Method probe was not successfully installed"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report('method instrumentation') do
        Target.new.test_method
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Method instrumentation did not work - callback was never invoked"
    end

    if calls < 1000 && !VALIDATE_BENCHMARK_MODE
      raise "Expected at least 1000 calls to the method, got #{calls}"
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
      file: file, line_no: line + 1)
    if defined?(Datadog::DI::ProcResponder)
      responder = Datadog::DI::ProcResponder.new(executed_proc)
      rv = instrumenter.hook_line(probe, responder)
    else
      rv = instrumenter.hook_line(probe, &executed_proc)
    end
    unless rv
      raise "Line probe (in method) was not successfully installed"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )
      x.report('line instrumentation - untargeted') do
        Target.new.test_method_for_line_probe
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Line instrumentation did not work - callback was never invoked"
    end

    if calls < 1000 && !VALIDATE_BENCHMARK_MODE
      raise "Expected at least 1000 calls to the method, got #{calls}"
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
      file: targeted_file, line_no: targeted_line + 1)
    rv = if defined?(Datadog::DI::ProcResponder)
      instrumenter.hook_line(probe, responder)
    else
      instrumenter.hook_line(probe, &executed_proc)
    end
    unless rv
      raise "Line probe (targeted) was not successfully installed"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(
        **benchmark_time,
      )

      x.report('line instrumentation - targeted') do
        DITarget.new.test_method_for_line_probe
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Targeted line instrumentation did not work - callback was never invoked"
    end

    if calls < 1000 && !VALIDATE_BENCHMARK_MODE
      raise "Expected at least 1000 calls to the method, got #{calls}"
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
