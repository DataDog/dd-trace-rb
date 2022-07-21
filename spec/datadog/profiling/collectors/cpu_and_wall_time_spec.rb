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
    let(:pprof_result) do
      serialization_result = recorder.serialize
      raise 'Unexpected: Serialization failed' unless serialization_result

      serialization_result.last
    end
    let(:samples) { samples_from_pprof(pprof_result) }

    it 'samples all threads' do
      all_threads = Thread.list

      cpu_and_wall_time_collector.sample

      expect(Thread.list).to eq(all_threads), 'Threads finished during this spec, causing flakiness!'
      expect(samples.size).to be all_threads.size
    end

    it 'tags the samples with the object ids of the Threads they belong to' do
      cpu_and_wall_time_collector.sample

      expect(samples.map { |it| it.fetch(:labels).fetch(:'thread id') })
        .to include(*[Thread.main, t1, t2, t3].map(&:object_id))
    end

    it 'includes the thread names, if available' do
      skip 'Thread names not available on Ruby 2.2' if RUBY_VERSION < '2.3'

      t1.name = 'thread t1'
      t2.name = nil
      t3.name = 'thread t3'

      cpu_and_wall_time_collector.sample

      t1_sample = samples.find { |it| it.fetch(:labels).fetch(:'thread id') == t1.object_id }
      t2_sample = samples.find { |it| it.fetch(:labels).fetch(:'thread id') == t2.object_id }
      t3_sample = samples.find { |it| it.fetch(:labels).fetch(:'thread id') == t3.object_id }

      expect(t1_sample).to include(labels: include(:'thread name' => 'thread t1'))
      expect(t2_sample.fetch(:labels).keys).to_not include(:'thread name')
      expect(t3_sample).to include(labels: include(:'thread name' => 'thread t3'))
    end

    it 'does not include thread names on Ruby 2.2' do
      skip 'Testcase only applies to Ruby 2.2' if RUBY_VERSION >= '2.3'

      expect(samples.flat_map { |it| it.fetch(:labels).keys }).to_not include(':thread name')
    end

    it 'includes the wall time elapsed between samples' do
      cpu_and_wall_time_collector.sample
      wall_time_at_first_sample =
        cpu_and_wall_time_collector.per_thread_context.fetch(t1).fetch(:wall_time_at_previous_sample_ns)

      cpu_and_wall_time_collector.sample
      wall_time_at_second_sample =
        cpu_and_wall_time_collector.per_thread_context.fetch(t1).fetch(:wall_time_at_previous_sample_ns)

      t1_samples = samples.select { |it| it.fetch(:labels).fetch(:'thread id') == t1.object_id }
      wall_time = t1_samples.first.fetch(:values).fetch(:'wall-time')

      expect(t1_samples.size)
        .to be(1), "Expected thread t1 to always have same stack trace (because it's sleeping), got #{t1_samples.inspect}"

      expect(wall_time).to be(wall_time_at_second_sample - wall_time_at_first_sample)
    end

    it 'tags samples with how many times they were seen' do
      5.times { cpu_and_wall_time_collector.sample }

      t1_sample = samples.find { |it| it.fetch(:labels).fetch(:'thread id') == t1.object_id }

      expect(t1_sample).to include(values: include(:'cpu-samples' => 5))
    end

    context 'cpu time behavior' do
      context 'when not on Linux' do
        before do
          skip 'The fallback behavior only applies when not on Linux' if PlatformHelpers.linux?
        end

        it 'sets the cpu-time on every sample to zero' do
          5.times { cpu_and_wall_time_collector.sample }

          expect(samples).to all include(values: include(:'cpu-time' => 0))
        end
      end

      context 'on Linux' do
        before do
          skip 'Test only runs on Linux' unless PlatformHelpers.linux?
        end

        it 'includes the cpu-time for the samples' do
          rspec_thread_spent_time = Datadog::Core::Utils::Time.measure(:nanosecond) do
            5.times { cpu_and_wall_time_collector.sample }
            samples # to trigger serialization
          end

          # The only thread we're guaranteed has spent some time on cpu is the rspec thread, so let's check we have
          # some data for it
          total_cpu_for_rspec_thread =
            samples
              .select { |it| it.fetch(:labels).fetch(:'thread id') == Thread.current.object_id }
              .map { |it| it.fetch(:values).fetch(:'cpu-time') }
              .reduce(:+)

          # The **wall-clock time** spent by the rspec thread is going to be an upper bound for the cpu time spent,
          # e.g. if it took 5 real world seconds to run the test, then at most the rspec thread spent those 5 seconds
          # running on CPU, but possibly it spent slightly less.
          expect(total_cpu_for_rspec_thread).to be_between(1, rspec_thread_spent_time)
        end
      end
    end
  end

  describe '#thread_list' do
    it "returns the same as Ruby's Thread.list" do
      expect(cpu_and_wall_time_collector.thread_list).to eq Thread.list
    end
  end

  describe '#per_thread_context' do
    context 'before sampling' do
      it do
        expect(cpu_and_wall_time_collector.per_thread_context).to be_empty
      end
    end

    context 'after sampling' do
      before do
        @wall_time_before_sample_ns = Datadog::Core::Utils::Time.get_time(:nanosecond)
        cpu_and_wall_time_collector.sample
        @wall_time_after_sample_ns = Datadog::Core::Utils::Time.get_time(:nanosecond)
      end

      it 'contains all the sampled threads' do
        expect(cpu_and_wall_time_collector.per_thread_context.keys).to include(Thread.main, t1, t2, t3)
      end

      it 'contains the thread ids (object_ids) of all sampled threads' do
        cpu_and_wall_time_collector.per_thread_context.each do |thread, context|
          expect(context.fetch(:thread_id)).to eq thread.object_id
        end
      end

      it 'sets the wall_time_at_previous_sample_ns to the current wall clock value' do
        expect(cpu_and_wall_time_collector.per_thread_context.values).to all(
          include(wall_time_at_previous_sample_ns: be_between(@wall_time_before_sample_ns, @wall_time_after_sample_ns))
        )
      end

      context 'cpu time behavior' do
        context 'when not on Linux' do
          before do
            skip 'The fallback behavior only applies when not on Linux' if PlatformHelpers.linux?
          end

          it 'sets the cpu_time_at_previous_sample_ns to zero' do
            expect(cpu_and_wall_time_collector.per_thread_context.values).to all(
              include(cpu_time_at_previous_sample_ns: 0)
            )
          end
        end

        context 'on Linux' do
          before do
            skip 'Test only runs on Linux' unless PlatformHelpers.linux?
          end

          it 'sets the cpu_time_at_previous_sample_ns to the current cpu clock value' do
            # It's somewhat difficult to validate the actual value since this is an operating system-specific value
            # which should only be assessed in relation to other values for the same thread, not in absolute
            expect(cpu_and_wall_time_collector.per_thread_context.values).to all(
              include(cpu_time_at_previous_sample_ns: not_be(0))
            )
          end

          it 'returns a bigger value for each sample' do
            sample_values = []

            3.times do
              cpu_and_wall_time_collector.sample

              sample_values <<
                cpu_and_wall_time_collector.per_thread_context[Thread.main].fetch(:cpu_time_at_previous_sample_ns)
            end

            expect(sample_values.uniq.size).to be(3), 'Every sample is expected to have a differ cpu time value'
            expect(sample_values).to eq(sample_values.sort), 'Samples are expected to be in ascending order'
          end
        end
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
