# typed: ignore

require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/cpu_and_wall_time'

RSpec.describe Datadog::Profiling::Collectors::CpuAndWallTime do
  before { skip_if_profiling_not_supported(self) }

  let(:recorder) { Datadog::Profiling::StackRecorder.new }
  let(:max_frames) { 123 }

  subject(:cpu_and_wall_time_collector) { described_class.new(recorder: recorder, max_frames: max_frames) }

  describe '#sample' do
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

  describe '#thread_list', :focus do
    let(:ready_queue) { Queue.new }
    let!(:t1) { Thread.new(ready_queue) { |ready_queue| ready_queue << true; sleep } }
    let!(:t2) { Thread.new(ready_queue) { |ready_queue| ready_queue << true; sleep } }
    let!(:t3) { Thread.new(ready_queue) { |ready_queue| ready_queue << true; sleep } }

    before do
      3.times { ready_queue.pop }
      expect(Thread.list).to include(Thread.main, t1, t2, t3)
    end

    after do
      [t1, t2, t3].each do |thread|
        thread.kill
        thread.join
      end
    end

    it "returns the same as Ruby's Thread.list" do
      expect(cpu_and_wall_time_collector.thread_list).to eq Thread.list
    end
  end
end
