require 'spec_helper'

require 'ddtrace/profiling/collectors/stack'
require 'ddtrace/profiling/recorder'

RSpec.describe Datadog::Profiling::Collectors::Stack do
  subject(:collector) { described_class.new(recorder, options) }
  let(:recorder) { instance_double(Datadog::Profiling::Recorder) }
  let(:options) { {} }

  describe '::new' do
    it 'with default settings' do
      is_expected.to have_attributes(
        enabled?: false,
        fork_policy: Datadog::Workers::Async::Thread::FORK_POLICY_RESTART,
        ignore_thread: nil,
        last_wall_time: kind_of(Float),
        loop_base_interval: described_class::MIN_INTERVAL,
        max_frames: described_class::DEFAULT_MAX_FRAMES,
        max_time_usage_pct: described_class::DEFAULT_MAX_TIME_USAGE_PCT,
        recorder: recorder
      )
    end
  end

  describe '#start' do
    subject(:start) { collector.start }

    it 'starts the worker' do
      expect(collector).to receive(:perform)
      start
    end
  end

  describe '#perform' do
    subject(:perform) { collector.perform }
    after { collector.stop(true, 0) }

    context 'when disabled' do
      before { collector.enabled = false }

      it 'does not start a worker thread' do
        is_expected.to be nil

        expect(collector).to have_attributes(
          run_async?: false,
          running?: false,
          started?: false,
          forked?: false,
          fork_policy: :restart,
          result: nil
        )
      end
    end

    context 'when enabled' do
      before { collector.enabled = true }

      it 'starts a worker thread' do
        allow(collector).to receive(:collect_events)

        is_expected.to be_a_kind_of(Thread)
        try_wait_until { collector.running? }

        expect(collector).to have_attributes(
          run_async?: true,
          running?: true,
          started?: true,
          forked?: false,
          fork_policy: :restart,
          result: nil
        )
      end
    end
  end

  describe '#loop_back_off?' do
    subject(:loop_back_off?) { collector.loop_back_off? }
    it { is_expected.to be false }
  end

  describe '#collect_and_wait' do
    subject(:collect_and_wait) { collector.collect_and_wait }
    let(:collect_time) { 0.05 }
    let(:updated_wait_time) { rand }

    before do
      expect(collector).to receive(:collect_events)
      allow(collector).to receive(:compute_wait_time)
        .with(collect_time)
        .and_return(updated_wait_time)

      allow(Datadog::Utils::Time).to receive(:measure) do |&block|
        block.call
        collect_time
      end
    end

    it 'changes its wait interval after collecting' do
      expect(collector).to receive(:loop_wait_time=)
        .with(updated_wait_time)

      collect_and_wait
    end
  end

  describe '#collect_events' do
    subject(:collect_events) { collector.collect_events }

    before do
      allow(recorder).to receive(:push)
    end

    context 'by default' do
      it 'produces stack events' do
        is_expected.to be_a_kind_of(Array)
        is_expected.to include(kind_of(Datadog::Profiling::Events::StackSample))
      end
    end

    context 'when the thread' do
      let(:thread) { instance_double(Thread, alive?: alive?) }
      let(:threads) { [thread] }
      let(:alive?) { true }

      before do
        allow(Thread).to receive(:list).and_return(threads)
      end

      context 'is dead' do
        let(:alive?) { false }

        it 'skips the thread' do
          expect(collector).to_not receive(:collect_thread_event)
          is_expected.to be_empty
          expect(recorder).to_not have_received(:push)
        end
      end

      context 'is ignored' do
        let(:options) { { ignore_thread: ->(t) { t == thread } } }

        it 'skips the thread' do
          expect(collector).to_not receive(:collect_thread_event)
          is_expected.to be_empty
          expect(recorder).to_not have_received(:push)
        end
      end

      context 'doesn\'t have an associated event' do
        before do
          expect(collector)
            .to receive(:collect_thread_event)
            .with(thread, kind_of(Float))
            .and_return(nil)
        end

        it 'no event is produced' do
          is_expected.to be_empty
          expect(recorder).to_not have_received(:push)
        end
      end

      context 'produces an event' do
        let(:event) { instance_double(Datadog::Profiling::Events::StackSample) }

        before do
          expect(collector)
            .to receive(:collect_thread_event)
            .with(thread, kind_of(Float))
            .and_return(event)
        end

        it 'records the event' do
          is_expected.to eq([event])
          expect(recorder).to have_received(:push).with([event])
        end
      end
    end
  end

  describe '#collect_thread_event' do
    subject(:collect_events) { collector.collect_thread_event(thread, wall_time_interval_ns) }
    let(:thread) { instance_double(Thread) }
    let(:wall_time_interval_ns) { double('wall time interval in nanoseconds') }

    before { allow(thread).to receive(:backtrace_locations).and_return(backtrace) }

    context 'when the backtrace is empty' do
      let(:backtrace) { nil }
      it { is_expected.to be nil }
    end

    context 'when the backtrace is not empty' do
      let(:backtrace) { Array.new(backtrace_size) { instance_double(Thread::Backtrace::Location) } }
      let(:backtrace_size) { collector.max_frames }

      it 'builds an event' do
        is_expected.to be_a_kind_of(Datadog::Profiling::Events::StackSample)

        is_expected.to have_attributes(
          timestamp: kind_of(Float),
          frames: backtrace,
          total_frame_count: backtrace.length,
          thread_id: thread.object_id,
          wall_time_interval_ns: wall_time_interval_ns
        )
      end

      context 'but is over the maximum length' do
        let(:backtrace_size) { collector.max_frames * 2 }

        it 'constrains the size of the backtrace' do
          is_expected.to have_attributes(total_frame_count: backtrace.length)

          collect_events.frames.tap do |frames|
            expect(frames).to be_a_kind_of(Array)
            expect(frames.length).to eq(collector.max_frames)
          end
        end
      end

      context 'and max_frames is 0' do
        let(:options) { { max_frames: 0 } }
        let(:backtrace_size) { described_class::DEFAULT_MAX_FRAMES * 2 }

        it 'does not constrain the size of the backtrace' do
          is_expected.to have_attributes(total_frame_count: backtrace.length)

          collect_events.frames.tap do |frames|
            expect(frames).to be_a_kind_of(Array)
            expect(frames.length).to eq(backtrace.length)
          end
        end
      end
    end
  end

  describe '#compute_wait_time' do
    subject(:compute_wait_time) { collector.compute_wait_time(used_time) }
    let(:used_time) { 1 }

    context 'when max time usage' do
      let(:options) { { max_time_usage_pct: max_time_usage_pct } }

      context 'is 100%' do
        let(:max_time_usage_pct) { 100.0 }

        it 'doesn\'t drop below the min interval' do
          is_expected.to eq described_class::MIN_INTERVAL
        end
      end

      context 'is 50%' do
        let(:max_time_usage_pct) { 50.0 }
        it { is_expected.to eq 1.0 }
      end

      context 'is 2%' do
        let(:max_time_usage_pct) { 2.0 }
        it { is_expected.to eq 49.0 }
      end
    end
  end
end
