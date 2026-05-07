# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'

# Measures the cost of a single heap sample on a deep Ruby stack.
#
# Each iteration: descend through STACK_DEPTH distinct iseqs (one eval'd method per level, so each
# frame is a fresh FunctionId/string insertion), sample BATCH_SIZE times, then drop the heap recorder
# state via a test hook (no GC involved).
#
# On the new-dictionary branch two reports are produced: one where the per-recorder frame caches are
# cleared before every sample (cold path — every sample walks the full build_location2_from_iseqs
# slow path) and one where the caches are left to warm up (steady-state path). On the legacy managed
# string table branch only the single report is produced; there is no per-recorder cache to reset.
#
# Per-object cost = iteration_time / BATCH_SIZE.

STACK_DEPTH = 300
BATCH_SIZE = 1_000

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

HAS_FRAME_CACHE_RESET = Datadog::Profiling::StackRecorder::Testing
  .respond_to?(:_native_benchmark_reset_frame_caches)

# Builds a chain of STACK_DEPTH methods (deep_stack_1 .. deep_stack_N), each a distinct iseq via
# string eval. Calling #run traverses the chain and yields at the bottom.
class DeepStackBuilder
  def initialize(depth)
    (1..depth).each do |d|
      body = (d == depth) ? 'yield' : "deep_stack_#{d + 1}(&block)"
      # rubocop:disable Security/Eval
      eval("def deep_stack_#{d}(&block); #{body}; end", binding, __FILE__, __LINE__)
      # rubocop:enable Security/Eval
    end
  end

  def run(&block)
    deep_stack_1(&block)
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

class ProfilerHeapSampleBenchmark
  def initialize
    @recorder = build_recorder
    @builder = DeepStackBuilder.new(STACK_DEPTH)
  end

  def sample_batch(reset_frame_caches:)
    recorder = @recorder
    stack_testing = Datadog::Profiling::Collectors::Stack::Testing
    recorder_testing = Datadog::Profiling::StackRecorder::Testing
    metric_values = METRIC_VALUES
    labels = LABELS
    numeric_labels = NUMERIC_LABELS
    alloc_class = ALLOC_CLASS
    thread = Thread.current

    BATCH_SIZE.times do
      recorder_testing._native_benchmark_reset_frame_caches(recorder) if reset_frame_caches
      recorder_testing._native_track_object(recorder, Object.new, 1, alloc_class)
      stack_testing._native_sample(thread, recorder, metric_values, labels, numeric_labels)
      recorder_testing._native_finalize_pending_heap_recordings(recorder)
    end
  end

  # Reports to run. On the new-dictionary branch: one with frame caches reset per sample (cold path)
  # and one without (warm path). On the legacy managed-string-table branch: only the single report.
  def reports
    if HAS_FRAME_CACHE_RESET
      [
        ["empty iseq cache", true],
        ["warm iseq cache", false],
      ]
    else
      [["legacy managed string table", false]]
    end
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? {time: 0.01, warmup: 0} : {time: 10, warmup: 2}
      x.config(**benchmark_time)

      reports.each do |name, reset_frame_caches|
        label = "heap sample (#{name}, stack depth #{STACK_DEPTH}, batch #{BATCH_SIZE}) #{ENV["CONFIG"]}"

        x.report(label) do
          @builder.run { sample_batch(reset_frame_caches: reset_frame_caches) }
          Datadog::Profiling::StackRecorder::Testing._native_benchmark_reset_heap_records(@recorder)
        end
      end

      x.save! "#{File.basename(__FILE__, '.rb')}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

ProfilerHeapSampleBenchmark.new.instance_exec do
  run_benchmark
end
