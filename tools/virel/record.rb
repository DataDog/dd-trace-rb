# frozen_string_literal: true

require "datadog/profiling"

abort "Usage: bundle exec ruby -Ilib tools/virel/record.rb OUTPUT.virl WORKLOAD.rb" unless ARGV.length == 2
abort Datadog::Profiling.unsupported_reason unless Datadog::Profiling.supported?
output, workload = ARGV.shift(2)

worker = Datadog::Profiling::Collectors::CpuAndWallTimeWorker.new(
  miteruby_enabled: true,
  thread_context_collector: nil,
  gc_profiling_enabled: false,
  no_signals_workaround_enabled: RUBY_VERSION < "2.6",
  dynamic_sampling_rate_overhead_target_percentage: 2.0,
  allocation_profiling_enabled: false,
  allocation_counting_enabled: false,
  gvl_profiling_enabled: false,
  sighandler_sampling_enabled: false,
  cpu_sampling_interval_ms: 10,
  waiting_for_gvl_threshold_ns: 10_000_000,
)
serializer = Datadog::Profiling::Miteruby::VirelSerializer.new
consumer = nil

begin
  worker.start
  worker.wait_until_running
  load workload
  worker.stop
  # The raw queue has one reader; join the worker's consumer before draining its unpublished tail.
  worker_class = Datadog::Profiling::Collectors::CpuAndWallTimeWorker
  consumer = Thread.new { worker_class._native_miteruby_consumer_consume_loop }
  until worker_class::Testing._native_miteruby_raw_events_queue_empty?
    consumer.value unless consumer.alive?
    Thread.pass
  end
  consumer.kill.join
  serializer.prepare_serialize
  File.binwrite(output, serializer.serialize!.bytes)
ensure
  worker.stop
  consumer&.kill&.join
end
