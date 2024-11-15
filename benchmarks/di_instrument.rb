=begin

"Instrumentation" part of Dynamic Instrumentation benchmarks.

Typical result:

Comparison:
  no instrumentation:   589490.0 i/s
method instrumentation - cleared:   545807.2 i/s - 1.08x  slower
line instrumentation - cleared:   539686.5 i/s - 1.09x  slower
no instrumentation - again:   535761.0 i/s - 1.10x  slower
method instrumentation:   129159.5 i/s - 4.56x  slower
line instrumentation - targeted:   128848.6 i/s - 4.58x  slower
line instrumentation:    10771.7 i/s - 54.73x  slower

Targeted line and method instrumentations have similar performance at
about 25% of baseline. Note that the instrumented method is fairly
small and probably runs very quickly by itself, so while this is not the
worst possible case for instrumentation (that would be an empty method),
likely the vast majority of real world uses of DI would have way expensive
target code and the relative overhead of instrumentation will be significantly
lower than it is in this benchmark.

Untargeted line instrumentation is extremely slow, too slow to be usable.

In theory, after instrumentation is removed, performance should return to
the baseline. We are currently observing about a 6-10% performance loss.
Two theories for why this is so:
1. Some overhead remains in the code - to be investigated.
2. The benchmarks were run on a laptop, and during the benchmarking
process the CPU is heating up and it can't turbo to the same speeds at
the end of the run as it can at the beginning. Meaning the observed 6-10%
slowdown at the end is an environmental issue and not an implementation
problem.

=end

# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'datadog'
# Need to require datadog/di explicitly because dynamic instrumentation is not
# currently integrated into the Ruby tracer due to being under development.
require 'datadog/di'

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

  def run_benchmark
    settings = Datadog.configuration
    # We benchmark untargeted and targeted trace points; untargeted ones
    # are prohibited by default, permit them.
    begin
      settings.dynamic_instrumentation.internal.untargeted_trace_points = true
    rescue NoMethodError
      settings.dynamic_instrumentation.untargeted_trace_points = true
    end
    redactor = Datadog::DI::Redactor.new(settings)
    serializer = Datadog::DI::Serializer.new(settings, redactor)
    logger = Logger.new(STDERR)
    instrumenter = Datadog::DI::Instrumenter.new(settings, serializer, logger)

    m = Target.instance_method(:test_method_for_line_probe)
    file, line = m.source_location

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('no instrumentation') do
        Target.new.test_method
      end

      x.save! 'di-instrument-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    calls = 0
    probe = Datadog::DI::Probe.new(id: 1, type: :log,
      type_name: 'DIInstrumentBenchmark::Target', method_name: 'test_method')
    instrumenter.hook_method(probe) do
      calls += 1
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('method instrumentation') do
        Target.new.test_method
      end

      x.save! 'di-instrument-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Method instrumentation did not work - callback was never invoked"
    end

    if calls < 1000 && !VALIDATE_BENCHMARK_MODE
      raise "Expected at least 1000 calls to the method, got #{calls}"
    end

    instrumenter.unhook(probe)

    calls = 0
    probe = Datadog::DI::Probe.new(id: 1, type: :log,
      file: file, line_no: line + 1)
    instrumenter.hook_line(probe) do
      calls += 1
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('line instrumentation') do
        Target.new.test_method_for_line_probe
      end

      x.save! 'di-instrument-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls < 1
      raise "Line instrumentation did not work - callback was never invoked"
    end

    if calls < 1000 && !VALIDATE_BENCHMARK_MODE
      raise "Expected at least 1000 calls to the method, got #{calls}"
    end

    Datadog::DI.activate_tracking!
    if defined?(DITarget)
      raise "DITarget is already defined, this should not happen"
    end
    require_relative 'support/di_target'
    unless defined?(DITarget)
      raise "DITarget is not defined, this should not happen"
    end

    m = DITarget.instance_method(:test_method_for_line_probe)
    targeted_file, targeted_line = m.source_location

    instrumenter.unhook(probe)
    calls = 0
    probe = Datadog::DI::Probe.new(id: 1, type: :log,
      file: targeted_file, line_no: targeted_line + 1)
    instrumenter.hook_line(probe) do
      calls += 1
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('line instrumentation - targeted') do
        DITarget.new.test_method_for_line_probe
      end

      x.save! 'di-instrument-results.json' unless VALIDATE_BENCHMARK_MODE
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
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      # This benchmark should produce identical results to the
      # "no instrumentation" benchmark.
      x.report('method instrumentation - cleared') do
        Target.new.test_method
      end

      x.save! 'di-instrument-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls != 0
      raise "Method instrumentation was not cleared (#{calls} calls recorded)"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      # This benchmark should produce identical results to the
      # "no instrumentation" benchmark.
      x.report('line instrumentation - cleared') do
        Target.new.test_method_for_line_probe
      end

      x.save! 'di-instrument-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    if calls != 0
      raise "Line instrumentation was not cleared (#{calls} calls recorded)"
    end

    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 10, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report('no instrumentation - again') do
        Target.new.not_instrumented
      end

      x.save! 'di-instrument-results.json' unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

  end

end

puts "Current pid is #{Process.pid}"

DIInstrumentBenchmark.new.instance_exec do
  run_benchmark
end
