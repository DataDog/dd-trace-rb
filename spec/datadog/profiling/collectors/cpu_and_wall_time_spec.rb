# typed: ignore

require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/cpu_and_wall_time'

RSpec.describe Datadog::Profiling::Collectors::CpuAndWallTime do
  before { skip_if_profiling_not_supported(self) }

  let(:recorder) { Datadog::Profiling::StackRecorder.new }
  let(:max_frames) { 123 }

  subject(:cpu_and_wall_time_collector) { described_class.new(recorder: recorder, max_frames: max_frames) }

  it 'samples all threads' do
    all_threads = Thread.list

    decoded_profile = sample_and_decode

    #binding.pry
  end

  def sample_and_decode
    cpu_and_wall_time_collector.sample

    serialization_result = recorder.serialize
    raise 'Unexpected: Serialization failed' unless serialization_result

    pprof_data = serialization_result.last
    decoded_profile = ::Perftools::Profiles::Profile.decode(pprof_data)

    decoded_profile
  end
end
