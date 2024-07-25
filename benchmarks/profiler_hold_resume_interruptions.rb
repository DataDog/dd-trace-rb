require_relative 'lib/boot'

# This benchmark measures the performance of the hold/resume interruptions used by the DirMonkeyPatches
Benchmarker.define(__FILE__) do

  def create_profiler
    Datadog.configure do |c|
      c.profiling.enabled = true
    end
    Datadog::Profiling.wait_until_running
  end

  before do
    create_profiler
  end

  benchmark('hold / resume') do
    Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
    Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
  end
end
