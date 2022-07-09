# typed: ignore

require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/cpu_and_wall_time'

RSpec.describe Datadog::Profiling::Collectors::CpuAndWallTime do
  before do
    skip_if_profiling_not_supported(self)

    [t1, t2, t3].each { ready_queue.pop }
    expect(Thread.list).to include(Thread.main, t1, t2, t3)
  end

  let(:recorder) { Datadog::Profiling::StackRecorder.new }
  let(:ready_queue) { Queue.new }
  let(:t1) do
    Thread.new(ready_queue) do |ready_queue|
      ready_queue << true
      sleep
    end
  end
  let(:t2) do
    Thread.new(ready_queue) do |ready_queue|
      ready_queue << true
      sleep
    end
  end
  let(:t3) do
    Thread.new(ready_queue) do |ready_queue|
      ready_queue << true
      sleep
    end
  end
  let(:max_frames) { 123 }

  subject(:cpu_and_wall_time_collector) { described_class.new(recorder: recorder, max_frames: max_frames) }

  after do
    [t1, t2, t3].each do |thread|
      thread.kill
      thread.join
    end
  end

  describe '#sample' do
    it 'samples all threads' do
      all_threads = Thread.list

      decoded_profile = sample_and_decode

      expect(decoded_profile.sample.size).to be all_threads.size
    end

    def sample_and_decode
      cpu_and_wall_time_collector.sample

      serialization_result = recorder.serialize
      raise 'Unexpected: Serialization failed' unless serialization_result

      pprof_data = serialization_result.last
      ::Perftools::Profiles::Profile.decode(pprof_data)
    end
  end

  describe '#thread_list' do
    it "returns the same as Ruby's Thread.list" do
      expect(cpu_and_wall_time_collector.thread_list).to eq Thread.list
    end
  end

  # Validate that we correctly clean up and don't leak per_thread_context
  describe '#per_thread_context' do
    context 'before sampling' do
      it do
        expect(cpu_and_wall_time_collector.per_thread_context).to be_empty
      end
    end

    context 'after sampling' do
      before do
        cpu_and_wall_time_collector.sample
      end

      it 'contains all the sampled threads' do
        expect(cpu_and_wall_time_collector.per_thread_context.keys).to include(Thread.main, t1, t2, t3)
      end
    end

    context 'after sampling multiple times' do
      it 'contains only the threads still alive' do
        cpu_and_wall_time_collector.sample

        # All alive threads still in there
        expect(cpu_and_wall_time_collector.per_thread_context.keys).to include(Thread.main, t1, t2, t3)

        # Get rid of t2
        t2.kill
        t2.join

        # Currently the clean-up gets triggered only every 100th sample, so we need to do this to trigger the
        # clean-up. This can probably be improved (see TODO on the actual implementation)
        100.times { cpu_and_wall_time_collector.sample }

        expect(cpu_and_wall_time_collector.per_thread_context.keys).to_not include(t2)
        expect(cpu_and_wall_time_collector.per_thread_context.keys).to include(Thread.main, t1, t3)
      end
    end
  end
end
