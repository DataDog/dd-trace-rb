# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'

# Measures the cost of serializing a heap profile.
#
# Setup: prime the heap recorder with TOTAL_OBJECTS tracked live objects spread across UNIQUE_STACKS
# distinct heap records (one per descent depth). References to every allocated object are held in
# @alive_objects so the set stays live across every serialize call; prepare_iteration always does a
# full update, so each measured serialize does the same work.
#
# Measurement: Benchmark.ips measures recorder.serialize! (the whole pipeline). After the run we do
# one extra serialize and print profile_stats so we can see what fraction of each iteration is
# heap_iteration_prep_time_ns vs heap_profile_build_time_ns vs the remaining pprof-encode cost.

STACK_DEPTH = 300
TOTAL_OBJECTS = VALIDATE_BENCHMARK_MODE ? 300 : 10_000
UNIQUE_STACKS = VALIDATE_BENCHMARK_MODE ? 30 : 300

METRIC_VALUES = {
  'cpu-time' => 0,
  'cpu-samples' => 0,
  'wall-time' => 0,
  'alloc-samples' => 1,
  'timeline' => 0,
  'heap_sample' => true,
}.freeze
LABELS = [].freeze
NUMERIC_LABELS = [].freeze
ALLOC_CLASS = 'Object'.freeze

# Builds a chain of max_depth methods (deep_stack_1 .. deep_stack_N), each a distinct iseq via
# string eval. #at_depth(target) descends to level `target` and yields from that frame.
class DeepStackBuilder
  def initialize(max_depth)
    (1..max_depth).each do |d|
      # rubocop:disable Security/Eval
      eval(
        "def deep_stack_#{d}(target, &block);" \
          " if #{d} >= target; yield;" \
          " else; deep_stack_#{d + 1}(target, &block);" \
          " end;" \
        "end",
        binding, __FILE__, __LINE__
      )
      # rubocop:enable Security/Eval
    end
  end

  def at_depth(target, &block)
    deep_stack_1(target, &block)
  end
end

def build_recorder
  base_args = {
    cpu_time_enabled: false,
    alloc_samples_enabled: false,
    heap_samples_enabled: true,
    heap_size_enabled: true,
    heap_sample_every: 1,
    timeline_enabled: false,
  }
  Datadog::Profiling::StackRecorder.for_testing(**base_args, dictionary_rotation_period: 0)
rescue ArgumentError
  # Legacy (managed-string-table) branch: `dictionary_rotation_period` kwarg does not exist yet.
  Datadog::Profiling::StackRecorder.for_testing(**base_args)
end

class ProfilerHeapSerializeBenchmark
  def initialize
    @recorder = build_recorder
    @builder = DeepStackBuilder.new(STACK_DEPTH)
    @alive_objects = []
    prime_heap_recorder
  end

  def prime_heap_recorder
    stack_testing = Datadog::Profiling::Collectors::Stack::Testing
    recorder_testing = Datadog::Profiling::StackRecorder::Testing
    recorder = @recorder
    alive = @alive_objects
    thread = Thread.current
    metric_values = METRIC_VALUES
    labels = LABELS
    numeric_labels = NUMERIC_LABELS
    alloc_class = ALLOC_CLASS
    builder = @builder

    TOTAL_OBJECTS.times do |i|
      depth = 1 + (i % UNIQUE_STACKS)
      builder.at_depth(depth) do
        obj = Object.new
        alive << obj
        recorder_testing._native_track_object(recorder, obj, 1, alloc_class)
        stack_testing._native_sample(thread, recorder, metric_values, labels, numeric_labels)
        recorder_testing._native_finalize_pending_heap_recordings(recorder)
      end
    end
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(**benchmark_time)

      label = "heap serialize (#{TOTAL_OBJECTS} objects, #{UNIQUE_STACKS} unique stacks, " \
        "stack depth #{STACK_DEPTH}) #{ENV["CONFIG"]}"

      x.report(label) { @recorder.serialize! }

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end

    return if VALIDATE_BENCHMARK_MODE

    # One extra serialize call to print the profile_stats breakdown so we can see what fraction of
    # each Benchmark.ips iteration is actually spent where.
    _start, _finish, _encoded_profile, profile_stats = @recorder.serialize
    puts "---"
    puts "Profile stats breakdown (single sample serialize after Benchmark.ips):"
    [:recorded_samples, :heap_iteration_prep_time_ns, :heap_profile_build_time_ns, :serialization_time_ns]
      .each { |k| puts "  #{k}: #{profile_stats[k]}" }
  end
end

puts "Current pid is #{Process.pid}"

ProfilerHeapSerializeBenchmark.new.instance_exec do
  run_benchmark
end
