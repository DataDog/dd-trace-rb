require 'spec_helper'

require 'ddtrace'
require 'ddtrace/profiling/pprof/builder'
require 'ddtrace/profiling/collectors/stack'
require 'ddtrace/profiling/recorder'
require 'ddtrace/profiling/scheduler'
require 'ddtrace/profiling/exporter'
require 'ddtrace/profiling/encoding/profile'

RSpec.describe 'profiling integration test' do
  let(:recorder) do
    Datadog::Profiling::Recorder.new(
      [Datadog::Profiling::Events::StackSample],
      100000
    )
  end
  let(:collector) do
    Datadog::Profiling::Collectors::Stack.new(
      recorder,
      enabled: true
    )
  end
  let(:exporter) do
    Datadog::Profiling::Exporter.new(
      Datadog::Transport::IO.default(
        encoder: Datadog::Profiling::Encoding::Profile::Protobuf,
        out: out
      )
    )
  end
  let(:out) { instance_double(IO) }
  let(:scheduler) do
    Datadog::Profiling::Scheduler.new(
      recorder,
      exporter,
      enabled: true
    )
  end
  let(:profiler) { Datadog::Profiling::Profiler.new }

  it 'produces a profile' do
    expect(out).to receive(:puts)
    collector.collect_events
    scheduler.flush_events
  end
end
