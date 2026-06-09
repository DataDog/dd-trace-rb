#
# Benchmarks the wrapper-allocation cost of candidate shapes for the DI
# method probe re-entrancy guard proposed in
# https://github.com/DataDog/dd-trace-rb/pull/5560.
#
# Background: PR #5560's wrapper allocates a fresh do_super lambda on every
# non-guarded invocation. Reviewers raised performance concerns. This
# benchmark compares the as-proposed shape against five candidate
# alternatives (block+yield, ruby2_keywords, super(...) literal, and
# combinations).
#
# This file is self-contained — it reimplements simplified versions of
# the wrapper shapes so it runs on master (which does not include the
# re-entrancy guard from PR #5560). The simplified wrappers preserve the
# allocation structure under measurement (Proc allocation vs block,
# kwargs/splat shape) while omitting the probe machinery (rate limiter,
# serializer, callbacks) that is identical across all shape variants and
# would not affect their relative comparison.
#
# Pure-Ruby in_probe?/array_empty?/hash_empty? are used in place of the C
# primitives from PR #5560's ext/libdatadog_api/di.c. The C versions
# bypass user-installed probes on Thread#[]/Array#empty?/Hash#empty?/
# Proc#call dispatch — a correctness property, not a relative-performance
# one. The pure-Ruby versions are equivalent across shape variants for
# the comparison.

# Used to quickly run benchmark under RSpec as part of the usual test
# suite, to validate it didn't bitrot.
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require 'benchmark/ips'
require 'json'

# Probe-state stand-in. The shipped wrapper uses DI.in_probe?/enter_probe/
# leave_probe implemented in C; this is the pure-Ruby equivalent.
module DIBench
  THREAD_KEY = :di_in_probe

  module_function

  def in_probe?
    Thread.current.thread_variable_get(THREAD_KEY) == true
  end

  def enter_probe
    Thread.current.thread_variable_set(THREAD_KEY, true)
  end

  def leave_probe
    Thread.current.thread_variable_set(THREAD_KEY, false)
  end
end

# The "instrumenter" stand-in. run_with_lambda receives the do_super
# lambda (baseline, B, C); run_with_yield runs the wrapper-passed block
# (A, AC, AD). probe_enabled toggles the disabled-at-install scenario.
class BenchInstrumenter
  attr_accessor :probe_enabled

  def initialize(probe_enabled: true)
    @probe_enabled = probe_enabled
  end

  def run_with_lambda(do_super, args, kwargs, blk)
    # Mimic PR #5560 run_method_probe: even when probe is disabled, the
    # do_super lambda has already been allocated by the wrapper.
    return do_super.call(args, kwargs, blk) unless @probe_enabled
    do_super.call(args, kwargs, blk)
  end

  def run_with_yield(args, kwargs, blk)
    return yield(args, kwargs, blk) unless @probe_enabled
    yield(args, kwargs, blk)
  end

  # Inline equivalent for shape B (super(...) literal); see WrapperShape.b_super_literal.
  def disabled?
    !@probe_enabled
  end
end

# Fixture method shapes.
class Fixture
  def noop_no_args
    nil
  end

  def noop_pos_args(a, b)
    a
  end

  def noop_kwargs(**opts)
    opts
  end

  def noop_both(a, **opts)
    a
  end

  def noop_block(&blk)
    blk
  end
end

# method_missing fixture for the 2.6 kwargs-forwarding constraint case.
class MMFixture
  def method_missing(name, *args, **kwargs, &blk)
    return super unless name == :virtual_method
    args
  end

  def respond_to_missing?(name, include_private = false)
    name == :virtual_method || super
  end
end

# Wrapper-shape builders. Each returns a Module that, when prepended to a
# class, wraps method_name with the shape's instrumentation pattern.
module WrapperShape
  module_function

  # baseline — as proposed in PR #5560 (do_super lambda + 4-way splat).
  def baseline(method_name, instrumenter)
    mod = Module.new
    mod.module_eval do
      define_method(method_name) do |*args, **kwargs, &target_block|
        if DIBench.in_probe?
          if !args.empty?
            if !kwargs.empty?
              return super(*args, **kwargs, &target_block)
            else
              return super(*args, &target_block)
            end
          elsif !kwargs.empty?
            return super(**kwargs, &target_block)
          else
            return super(&target_block)
          end
        end

        do_super = ->(a, k, blk) {
          if !a.empty?
            if !k.empty?
              super(*a, **k, &blk)
            else
              super(*a, &blk)
            end
          elsif !k.empty?
            super(**k, &blk)
          else
            super(&blk)
          end
        }

        instrumenter.run_with_lambda(do_super, args, kwargs, target_block)
      end
    end
    mod
  end

  # A — block + yield instead of lambda.
  def a_block_yield(method_name, instrumenter)
    mod = Module.new
    mod.module_eval do
      define_method(method_name) do |*args, **kwargs, &target_block|
        if DIBench.in_probe?
          if !args.empty?
            if !kwargs.empty?
              return super(*args, **kwargs, &target_block)
            else
              return super(*args, &target_block)
            end
          elsif !kwargs.empty?
            return super(**kwargs, &target_block)
          else
            return super(&target_block)
          end
        end

        instrumenter.run_with_yield(args, kwargs, target_block) do |a, k, blk|
          if !a.empty?
            if !k.empty?
              super(*a, **k, &blk)
            else
              super(*a, &blk)
            end
          elsif !k.empty?
            super(**k, &blk)
          else
            super(&blk)
          end
        end
      end
    end
    mod
  end

  # B — super(...) literal via class_eval (2.7+).
  # super(...) cannot be captured inside a lambda, so this shape inlines
  # the probe-disabled fast path and the active path. The "active" path
  # here calls super(...) directly after recording the call; this is the
  # most optimistic shape for B.
  def b_super_literal(method_name, instrumenter)
    return nil unless RUBY_VERSION >= "2.7"
    mod = Module.new
    # The instrumenter is captured in the class_eval'd code via a Module
    # constant. Using a constant rather than an instance variable so the
    # class_eval'd method can reach it without ivar lookup gymnastics.
    mod.const_set(:INSTR, instrumenter)
    mod.module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
      def #{method_name}(...)
        if DIBench.in_probe?
          return super(...)
        end
        # No do_super lambda; super(...) is called directly. This is the
        # shape's core advantage — zero Proc allocation on the hot path.
        if INSTR.disabled?
          return super(...)
        end
        super(...)
      end
    RUBY
    mod
  end

  # C — ruby2_keywords (2.7+). Single *args splat, kwargs flow through as
  # a flagged hash. do_super lambda is still allocated but with only two
  # args (a, blk) instead of three (a, k, blk).
  def c_ruby2_keywords(method_name, instrumenter)
    return nil unless RUBY_VERSION >= "2.7"
    mod = Module.new
    mod.module_eval do
      define_method(method_name) do |*args, &target_block|
        if DIBench.in_probe?
          return super(*args, &target_block)
        end

        do_super = ->(a, _k, blk) { super(*a, &blk) }
        instrumenter.run_with_lambda(do_super, args, nil, target_block)
      end
      ruby2_keywords method_name
    end
    mod
  end

  # AC — A + C combined: block+yield + ruby2_keywords.
  def ac_combined(method_name, instrumenter)
    return nil unless RUBY_VERSION >= "2.7"
    mod = Module.new
    mod.module_eval do
      define_method(method_name) do |*args, &target_block|
        if DIBench.in_probe?
          return super(*args, &target_block)
        end

        instrumenter.run_with_yield(args, nil, target_block) do |a, _k, blk|
          super(*a, &blk)
        end
      end
      ruby2_keywords method_name
    end
    mod
  end

  # AD — A + simplified guarded path. The guarded path collapses to a
  # single super(*args, **kwargs, &blk) call rather than the 4-way splat.
  def ad_combined(method_name, instrumenter)
    mod = Module.new
    mod.module_eval do
      define_method(method_name) do |*args, **kwargs, &target_block|
        if DIBench.in_probe?
          # Simplified single-shape guarded path (D).
          return super(*args, **kwargs, &target_block)
        end

        # Block + yield non-guarded path (A).
        instrumenter.run_with_yield(args, kwargs, target_block) do |a, k, blk|
          if !a.empty?
            if !k.empty?
              super(*a, **k, &blk)
            else
              super(*a, &blk)
            end
          elsif !k.empty?
            super(**k, &blk)
          else
            super(&blk)
          end
        end
      end
    end
    mod
  end
end

SHAPE_BUILDERS = {
  'baseline' => WrapperShape.method(:baseline),
  'A'        => WrapperShape.method(:a_block_yield),
  'B'        => WrapperShape.method(:b_super_literal),
  'C'        => WrapperShape.method(:c_ruby2_keywords),
  'AC'       => WrapperShape.method(:ac_combined),
  'AD'       => WrapperShape.method(:ad_combined),
}.freeze

# Fixture / method / call invocation per fixture.
# Each entry: [fixture_class, method_name, lambda_invoking_method_on(instance)]
FIXTURES = {
  'noop_no_args'    => [Fixture,   :noop_no_args,    ->(o) { o.noop_no_args } ],
  'noop_pos_args'   => [Fixture,   :noop_pos_args,   ->(o) { o.noop_pos_args(1, 2) } ],
  'noop_kwargs'     => [Fixture,   :noop_kwargs,     ->(o) { o.noop_kwargs(a: 1, b: 2) } ],
  'noop_both'       => [Fixture,   :noop_both,       ->(o) { o.noop_both(1, b: 2) } ],
  'noop_block'      => [Fixture,   :noop_block,      ->(o) { o.noop_block { } } ],
  'noop_method_missing' => [MMFixture, :virtual_method, ->(o) { o.virtual_method(1, a: 2) } ],
}.freeze

# Build a wrapped class for the given shape + fixture, returning an
# instance ready to be called. Returns nil if the shape doesn't apply
# (e.g., ruby2_keywords on 2.6).
def build_wrapped_instance(shape_name, fixture_name, instrumenter)
  fixture_class, method_name, _caller = FIXTURES.fetch(fixture_name)
  builder = SHAPE_BUILDERS.fetch(shape_name)
  mod = builder.call(method_name, instrumenter)
  return nil if mod.nil?

  # Subclass the fixture so each (shape, fixture) combo gets its own
  # class hierarchy — prepended modules can't be cleanly removed.
  klass = Class.new(fixture_class)
  klass.prepend(mod)
  klass.new
end

SCENARIOS = %w[unwrapped wrapped_not_in_probe wrapped_in_probe wrapped_disabled].freeze

# Run one (fixture, scenario) Benchmark.ips block comparing all shapes.
def run_ips_block(fixture_name, scenario, config)
  _fixture_class, _method_name, invoke = FIXTURES.fetch(fixture_name)
  base_instance = FIXTURES.fetch(fixture_name).first.new

  out_name = "di_method_probe_wrapper-#{fixture_name}-#{scenario}-results.json"

  Benchmark.ips do |x|
    x.config(**config)

    if scenario == 'unwrapped'
      x.report("#{fixture_name} unwrapped") { invoke.call(base_instance) }
    else
      SHAPE_BUILDERS.each_key do |shape|
        probe_enabled = scenario != 'wrapped_disabled'
        instrumenter = BenchInstrumenter.new(probe_enabled: probe_enabled)
        instance = build_wrapped_instance(shape, fixture_name, instrumenter)
        next if instance.nil?

        if scenario == 'wrapped_in_probe'
          DIBench.enter_probe
          x.report("#{fixture_name} #{scenario} #{shape}") { invoke.call(instance) }
          DIBench.leave_probe
        else
          x.report("#{fixture_name} #{scenario} #{shape}") { invoke.call(instance) }
        end
      end
    end

    x.save!(out_name) unless VALIDATE_BENCHMARK_MODE
    x.compare!
  end
end

# Allocation pass: GC.stat(:total_allocated_objects) delta over N calls
# per (shape, fixture, scenario). Returns objects/op.
def measure_allocations(fixture_name, scenario, iterations)
  _fixture_class, _method_name, invoke = FIXTURES.fetch(fixture_name)

  results = {}

  if scenario == 'unwrapped'
    instance = FIXTURES.fetch(fixture_name).first.new
    # Warm + measure
    iterations.times { invoke.call(instance) }
    GC.start
    before = GC.stat(:total_allocated_objects)
    iterations.times { invoke.call(instance) }
    after = GC.stat(:total_allocated_objects)
    results['unwrapped'] = (after - before).to_f / iterations
    return results
  end

  SHAPE_BUILDERS.each_key do |shape|
    probe_enabled = scenario != 'wrapped_disabled'
    instrumenter = BenchInstrumenter.new(probe_enabled: probe_enabled)
    instance = build_wrapped_instance(shape, fixture_name, instrumenter)
    next if instance.nil?

    DIBench.enter_probe if scenario == 'wrapped_in_probe'
    begin
      iterations.times { invoke.call(instance) }
      GC.start
      before = GC.stat(:total_allocated_objects)
      iterations.times { invoke.call(instance) }
      after = GC.stat(:total_allocated_objects)
      results[shape] = (after - before).to_f / iterations
    ensure
      DIBench.leave_probe if scenario == 'wrapped_in_probe'
    end
  end

  results
end

# ---------- main ----------

puts "Ruby: #{RUBY_DESCRIPTION}"
puts "PID: #{Process.pid}"
puts

bench_config = if VALIDATE_BENCHMARK_MODE
  {time: 0.01, warmup: 0}
elsif ENV['QUICK_BENCHMARK'] == 'true'
  {time: 1, warmup: 0.5}
else
  {time: 3, warmup: 1}
end

alloc_iterations = if VALIDATE_BENCHMARK_MODE
  100
elsif ENV['QUICK_BENCHMARK'] == 'true'
  10_000
else
  50_000
end

puts "benchmark-ips config: warmup=#{bench_config[:warmup]}s, measure=#{bench_config[:time]}s"
puts "allocation iterations per cell: #{alloc_iterations}"
puts

# Phase 1: benchmark-ips wall time
FIXTURES.each_key do |fixture|
  SCENARIOS.each do |scenario|
    next if scenario == 'unwrapped' && fixture != FIXTURES.keys.first && VALIDATE_BENCHMARK_MODE
    puts "\n=== #{fixture} / #{scenario} ==="
    run_ips_block(fixture, scenario, bench_config)
  end
end

# Phase 2: allocations
unless VALIDATE_BENCHMARK_MODE
  puts "\n\n========== ALLOCATIONS (objects/call) =========="
  alloc_results = {}
  FIXTURES.each_key do |fixture|
    alloc_results[fixture] = {}
    SCENARIOS.each do |scenario|
      alloc_results[fixture][scenario] = measure_allocations(fixture, scenario, alloc_iterations)
    end
  end

  # Print allocation table
  SCENARIOS.each do |scenario|
    puts "\n--- #{scenario} ---"
    header = ['fixture'.ljust(22)] + SHAPE_BUILDERS.keys.map { |s| s.ljust(10) }
    header.unshift('unwrapped'.ljust(10)) if scenario == 'unwrapped'
    puts header.join(' ')
    FIXTURES.each_key do |fixture|
      row = [fixture.ljust(22)]
      if scenario == 'unwrapped'
        v = alloc_results[fixture][scenario]['unwrapped']
        row << format('%.2f', v).ljust(10)
      else
        SHAPE_BUILDERS.each_key do |shape|
          v = alloc_results[fixture][scenario][shape]
          row << (v ? format('%.2f', v).ljust(10) : 'n/a'.ljust(10))
        end
      end
      puts row.join(' ')
    end
  end

  File.write(
    'di_method_probe_wrapper-allocations-results.json',
    JSON.pretty_generate(alloc_results)
  )
  puts "\nAllocation data written to di_method_probe_wrapper-allocations-results.json"
end
