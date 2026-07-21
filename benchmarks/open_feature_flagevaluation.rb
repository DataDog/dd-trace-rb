# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV["VALIDATE_BENCHMARK"] == "true"

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative "benchmarks_helper"
require "datadog/open_feature/flag_evaluation/aggregator"
require "datadog/open_feature/flag_evaluation/writer"
require "datadog/open_feature/hooks/flag_eval_evp_hook"

# Benchmarks the EVP flagevaluation eval-time hot path:
#   1. the OpenFeature `finally` hook (cheap capture + non-blocking enqueue) — what the user's
#      evaluation thread actually pays per evaluation, and
#   2. the background aggregation `record` (flatten -> prune -> canonical key -> two-tier bucket),
#      which the single writer thread pays off the eval path.
#
# The design goal is that the eval thread only pays (1); (2) is amortized on the worker. These
# numbers quantify both so regressions in either are visible. The profiles mirror the Go
# OpenFeature EVP benchmark suite so Ruby also covers the team's >=2,500 flag scale target.
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
  HookDetails = Struct.new(:variant, :reason, :error_code, :flag_metadata)
  BenchmarkProfile = Struct.new(:name, :num_flags, :num_users, :num_fields)

  SCALE_PROFILE_NAME = "scale/2500flags_500users_20fields"
  BENCHMARK_PROFILES = [
    BenchmarkProfile.new("typical/100flags_50users_10fields", 100, 50, 10),
    BenchmarkProfile.new("stress/10flags_1000users_250fields", 10, 1_000, 250),
    # Scale profile targets the team's >=2,500-flag goal. Flag count is the dimension under
    # test, so it dominates; users/fields are kept modest so context cost does not swamp it.
    BenchmarkProfile.new(SCALE_PROFILE_NAME, 2_500, 500, 20),
  ].freeze

  def benchmark_time(time: 12, warmup: 2)
    VALIDATE_BENCHMARK_MODE ? {time: 0.001, warmup: 0} : {time: time, warmup: warmup}
  end

  def benchmark_results_file(suffix)
    "#{File.basename(__FILE__, ".rb")}-#{suffix}-results.json"
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
    @writer.define_singleton_method(:start_background_thread) {}

    @hook = Datadog::OpenFeature::Hooks::FlagEvalEVPHook.new(@writer)

    @details = HookDetails.new("variant-on", "TARGETING_MATCH", nil, {
      "__dd_allocation_key" => "allocation-7",
      "dd.eval.timestamp_ms" => 1_760_000_000_000,
    })

    @attrs_by_profile = BENCHMARK_PROFILES.each_with_object({}) do |profile, attrs_by_profile|
      attrs_by_profile[profile.name] = make_benchmark_attrs(profile.num_fields)
    end

    @hook_contexts_by_profile = BENCHMARK_PROFILES.each_with_object({}) do |profile, contexts_by_profile|
      contexts_by_profile[profile.name] = HookContext.new(
        "bench-flag-#{profile.num_flags}",
        EvpEvalContext.new("bench-user-#{profile.num_users}", @attrs_by_profile[profile.name]),
      )
    end

    @flag_keys_by_profile = BENCHMARK_PROFILES.each_with_object({}) do |profile, keys_by_profile|
      keys_by_profile[profile.name] = Array.new(profile.num_flags) { |i| "bench-flag-#{i}" }
    end

    @targeting_keys_by_profile = BENCHMARK_PROFILES.each_with_object({}) do |profile, keys_by_profile|
      keys_by_profile[profile.name] = Array.new(profile.num_users) { |i| "bench-user-#{i}" }
    end
  end

  def make_benchmark_attrs(num_fields)
    # The targeting key is supplied separately, so this builds num_fields - 1 context attrs.
    (1...num_fields).each_with_object({}) do |i, attrs|
      attrs["field#{i}"] = "value"
    end
  end

  def scale_profile
    BENCHMARK_PROFILES.find { |profile| profile.name == SCALE_PROFILE_NAME } ||
      raise("scale profile #{SCALE_PROFILE_NAME} missing from BENCHMARK_PROFILES")
  end

  # Eval-thread hot path: the OpenFeature finally hook (capture + non-blocking enqueue).
  def benchmark_hook_finally
    Benchmark.ips do |x|
      x.config(**benchmark_time)

      BENCHMARK_PROFILES.each do |profile|
        hook_context = @hook_contexts_by_profile.fetch(profile.name)
        x.report("hook#finally/#{profile.name} (eval-thread capture + enqueue)") do
          @hook.finally(hook_context: hook_context, evaluation_details: @details)
          # Keep the bounded queue from filling during the benchmark (drain cheaply).
          drain_writer_queue
        end
      end

      x.save!(benchmark_results_file("hook-finally")) unless VALIDATE_BENCHMARK_MODE
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

      BENCHMARK_PROFILES.each do |profile|
        attrs = @attrs_by_profile.fetch(profile.name)
        flag_keys = @flag_keys_by_profile.fetch(profile.name)
        targeting_keys = @targeting_keys_by_profile.fetch(profile.name)
        aggregator = Datadog::OpenFeature::FlagEvaluation::Aggregator.new
        counter = 0

        x.report("aggregator#record/#{profile.name} (worker-thread aggregation)") do
          aggregator.record(
            flag_key: flag_keys[counter % flag_keys.length],
            variant: "variant-on",
            allocation_key: "allocation-7",
            targeting_key: targeting_keys[counter % targeting_keys.length],
            eval_time_ms: 1_760_000_000_000 + counter,
            attrs: attrs,
          )
          counter += 1
        end
      end

      x.save!(benchmark_results_file("aggregator-record")) unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  # Threaded worker hot path at the >=2,500-flag scale profile. This is Ruby's closest analogue
  # to Go's RunParallel benchmark: persistent workers avoid per-sample thread creation while
  # still exercising the synchronized aggregator under concurrent producers.
  def benchmark_aggregator_record_parallel_scale
    profile = scale_profile
    attrs = @attrs_by_profile.fetch(profile.name)
    flag_keys = @flag_keys_by_profile.fetch(profile.name)
    targeting_keys = @targeting_keys_by_profile.fetch(profile.name)
    aggregator = Datadog::OpenFeature::FlagEvaluation::Aggregator.new
    jobs = Queue.new
    done = Queue.new
    worker_count = 8
    records_per_worker = 32
    records_per_sample = worker_count * records_per_worker

    workers = Array.new(worker_count) do |worker_index|
      Thread.new do
        counter = worker_index
        loop do
          records = jobs.pop
          break if records == :stop

          records.times do
            aggregator.record(
              flag_key: flag_keys[counter % flag_keys.length],
              variant: "variant-on",
              allocation_key: "allocation-7",
              targeting_key: targeting_keys[counter % targeting_keys.length],
              eval_time_ms: 1_760_000_000_000 + counter,
              attrs: attrs,
            )
            counter += worker_count
          end
          done << true
        end
      end
    end

    Benchmark.ips do |x|
      x.config(**benchmark_time)
      x.report("aggregator#record/parallel/#{profile.name} (#{records_per_sample} records/sample)") do
        worker_count.times { jobs << records_per_worker }
        worker_count.times { done.pop }
      end
      x.save!(benchmark_results_file("aggregator-record-parallel")) unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  ensure
    workers&.each { jobs << :stop }
    workers&.each(&:join)
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
  run_benchmark { benchmark_aggregator_record_parallel_scale }
end
