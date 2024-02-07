require 'ddtrace'
require 'pry'

@recorder = Datadog::Profiling::StackRecorder.new(
  cpu_time_enabled: true,
  alloc_samples_enabled: false,
  heap_samples_enabled: false,
  heap_size_enabled: false,
  heap_sample_every: 1,
  timeline_enabled: true,
)
@collector = Datadog::Profiling::Collectors::ThreadContext.new(
  recorder: @recorder, max_frames: 400, tracer: Datadog.send(:components).tracer, endpoint_collection_enabled: false, timeline_enabled: true
)
PROFILER_OVERHEAD_STACK_THREAD = Thread.main

LOOP_STARTED = Queue.new
THREAD_SHOULD_SLEEP = Queue.new
FINISH = Queue.new

test_thread = Thread.new do
  Datadog::Tracing.trace('test') do
    3.times do
      LOOP_STARTED << true
      nil while THREAD_SHOULD_SLEEP.empty?
      Datadog::Tracing.trace('nested') do
        THREAD_SHOULD_SLEEP.pop
        begin
          sleep
        rescue
        end
      end
    end
    puts "Sleeping to create long trace"
    FINISH.pop
    puts "Woken up!"
  end
end

3.times do
  3.times { Thread.pass }
  LOOP_STARTED.pop
  3.times { Thread.pass }

  # Thread is looping
  Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)

  # Make it sleep
  THREAD_SHOULD_SLEEP << true

  # Give it time to get to sleep
  3.times { Thread.pass }

  # Blame some remainder cpu-time on sleep
  Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)

  # ...and now this is a sleep
  Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)

  test_thread.raise(StandardError.new("wake up!"))
end

# 70.times {
#   sleep 1
#   Datadog::Profiling::Collectors::ThreadContext::Testing._native_sample(@collector, PROFILER_OVERHEAD_STACK_THREAD)
# }
FINISH << true
test_thread.join
# sleep 1 # make sure we have minimum profile length

class FakeTimeProvider
  def self.now
    self
  end

  def self.utc
    Time.now.utc - 60
  end
end

flush = Datadog::Profiling::Exporter.new(
  pprof_recorder: @recorder,
  code_provenance_collector: nil,
  internal_metadata: {},
  time_provider: FakeTimeProvider,
).flush

Datadog::Profiling::HttpTransport.new(
  agent_settings: Datadog::Core::Configuration::AgentSettingsResolver.call(Datadog.configuration, logger: @logger),
  site: nil,
  api_key: nil,
  upload_timeout_seconds: 30,
).export(flush)

Datadog.shutdown!
