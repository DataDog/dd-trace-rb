# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'

class CaptureFlush
  attr_reader :flush
  def export(flush)
    @flush = flush
  end
  INSTANCE = new
end

Datadog.configure do |c|
  c.profiling.enabled = true
  c.profiling.exporter.transport = CaptureFlush::INSTANCE
  # c.profiling.advanced.experimental_cpu_sampling_interval_ms = 1 # TODO
end
Datadog::Profiling.wait_until_running

DURATION = VALIDATE_BENCHMARK_MODE ? 1.0 : 10.0

sleep DURATION

Datadog.shutdown!

flush = CaptureFlush::INSTANCE.flush

require "zstd-ruby"
File.write("profiler-sample-overhead.pprof", Zstd.decompress(flush.encoded_profile._native_bytes))

data = JSON.load(flush.internal_metadata_json)
duration = flush.finish - flush.start
duration_ns = duration * 1e9
samples = data.dig("worker_stats", "cpu_sampled")
cpu_sampling_time_ns_total = data.dig("worker_stats", "cpu_sampling_time_ns_total")
serialization_time_ns_total = data.dig("recorder_stats", "serialization_time_ns_total")
inactive_thread_samples_skipped = data.dig("worker_stats", "inactive_thread_samples_skipped")

overhead = -> total {
  "%.2f%%" % ((total / duration_ns) * 100.0)
}

pp data

pp({
  duration: duration,
  samples: samples,
  trigger_simulated_signal_delivery_attempts: data.dig("worker_stats", "trigger_simulated_signal_delivery_attempts"),
  cpu_sampling_time_ns_total: cpu_sampling_time_ns_total,
  cpu_sampling_overhead: overhead[cpu_sampling_time_ns_total],
  serialization_time_ns_total: serialization_time_ns_total,
  serialization_overhead: overhead[serialization_time_ns_total],
  sampling_rate: samples / duration,
  sample_every_n_ms: (duration / samples) * 1000,
  inactive_thread_samples_skipped: inactive_thread_samples_skipped,
})


# idea for test: 1 thread doing CPU work and changing its stack, 1 thread sleeping, assert #samples smaller for sleeping thread
