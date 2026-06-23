# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'
require 'datadog/open_feature/flagevaluation/aggregator'
require 'datadog/open_feature/flagevaluation/writer'
require 'datadog/open_feature/hooks/flag_eval_logging_hook'

# Benchmarks the EVP flagevaluation eval-time hot path:
#   1. the OpenFeature `finally` hook (cheap capture + non-blocking enqueue) — what the user's
#      evaluation thread actually pays per evaluation, and
#   2. the background aggregation `record` (flatten -> prune -> canonical key -> two-tier bucket),
#      which the single writer thread pays off the eval path.
#
# The design goal is that the eval thread only pays (1); (2) is amortized on the worker. These
# numbers quantify both so regressions in either are visible.
class OpenFeatureFlagevaluationBenchmark
  # A transport that swallows sends so the writer never does network I/O during the benchmark.
  class NoopTransport
    def send_flag_evaluations(_payload)
      # no-op
    end
  end

  # Duck-typed hook inputs (mirror Provider::EvpEvalContext / HookContext / HookDetails).
  EvpEvalContext = Struct.new(:targeting_key, :attributes)
  HookContext = Struct.new(:flag_key, :evaluation_context)
  HookDetails = Struct.new(:variant, :reason, :flag_metadata)

  def benchmark_time(time: 12, warmup: 2)
    VALIDATE_BENCHMARK_MODE ? {time: 0.001, warmup: 0} : {time: time, warmup: warmup}
  end

  def initialize
    @writer = Datadog::OpenFeature::FlagEvaluation::Writer.allocate
    # Build the writer without starting the real background thread (we drive aggregation directly).
    @writer.instance_variable_set(:@transport, NoopTransport.new)
    @writer.instance_variable_set(:@logger, Datadog.logger)
    @writer.instance_variable_set(:@aggregator, Datadog::OpenFeature::FlagEvaluation::Aggregator.new)
    @writer.instance_variable_set(:@queue, SizedQueue.new(Datadog::OpenFeature::FlagEvaluation::Writer::QUEUE_SIZE))
    @writer.instance_variable_set(:@stop_mutex, Mutex.new)
    @writer.instance_variable_set(:@dropped_queue_overflow, 0)

    @hook = Datadog::OpenFeature::Hooks::FlagEvalLoggingHook.new(@writer)
    @aggregator = Datadog::OpenFeature::FlagEvaluation::Aggregator.new

    @hook_context = HookContext.new(
      'bench-flag',
      EvpEvalContext.new('user-12345', {'env' => 'prod', 'plan' => 'enterprise', 'region' => 'us1'}),
    )
    @details = HookDetails.new('variant-on', 'TARGETING_MATCH', {
      '__dd_allocation_key' => 'allocation-7',
      'dd.eval.timestamp_ms' => 1_760_000_000_000,
    })

    @record_args = {
      flag_key: 'bench-flag', variant: 'variant-on', allocation_key: 'allocation-7',
      targeting_key: 'user-12345', eval_time_ms: 1_760_000_000_000,
      attrs: {'env' => 'prod', 'plan' => 'enterprise', 'region' => 'us1'},
    }
  end

  # Eval-thread hot path: the OpenFeature finally hook (capture + non-blocking enqueue).
  def benchmark_hook_finally
    Benchmark.ips do |x|
      x.config(**benchmark_time)
      x.report('hook#finally (eval-thread capture + enqueue)') do
        @hook.finally(hook_context: @hook_context, evaluation_details: @details)
        # Keep the bounded queue from filling during the benchmark (drain cheaply).
        drain_writer_queue
      end
      x.save!("#{File.basename(__FILE__, ".rb")}-results.json") unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def drain_writer_queue
    queue = @writer.instance_variable_get(:@queue)
    queue.pop(true) until queue.empty?
  rescue ThreadError
    # Nonblocking pop raises when another consumer drains the queue first.
  end

  # Worker hot path: full aggregation of one event (flatten + prune + canonical key + bucket).
  def benchmark_aggregator_record
    Benchmark.ips do |x|
      x.config(**benchmark_time)
      x.report('aggregator#record (worker-thread aggregation)') do
        @aggregator.record(**@record_args)
      end
      x.save!("#{File.basename(__FILE__, ".rb")}-results.json") unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end
end

puts "Current pid is #{Process.pid}"

def run_benchmark(&block)
  if VALIDATE_BENCHMARK_MODE
    block.call
  else
    # Forking to avoid state leaking between benchmarks
    pid = fork(&block)
    _, status = Process.wait2(pid)

    raise "Benchmark failed with status #{status}" unless status.success?
  end
end

OpenFeatureFlagevaluationBenchmark.new.instance_exec do
  run_benchmark { benchmark_hook_finally }
  run_benchmark { benchmark_aggregator_record }
end
