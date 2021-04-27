require 'spec_helper'

require 'ddtrace/profiling/exporter'
require 'ddtrace/profiling/recorder'
require 'ddtrace/profiling/scheduler'

RSpec.describe Datadog::Profiling::Scheduler do
  subject(:scheduler) { described_class.new(recorder, exporters, **options) }

  let(:recorder) { instance_double(Datadog::Profiling::Recorder) }
  let(:exporters) { [instance_double(Datadog::Profiling::Exporter)] }
  let(:options) { {} }

  describe '::new' do
    it 'with default settings' do
      is_expected.to have_attributes(
        enabled?: true,
        exporters: exporters,
        fork_policy: Datadog::Workers::Async::Thread::FORK_POLICY_RESTART,
        loop_base_interval: described_class::DEFAULT_INTERVAL_SECONDS,
        recorder: recorder
      )
    end

    context 'given a single exporter' do
      let(:exporters) { instance_double(Datadog::Profiling::Exporter) }

      it { is_expected.to have_attributes(exporters: [exporters]) }
    end
  end

  describe '#start' do
    subject(:start) { scheduler.start }

    it 'starts the worker' do
      expect(scheduler).to receive(:perform)
      start
    end
  end

  describe '#perform' do
    subject(:perform) { scheduler.perform }

    after do
      scheduler.stop(true, 0)
      scheduler.join
    end

    context 'when disabled' do
      before { scheduler.enabled = false }

      it 'does not start a worker thread' do
        perform

        expect(scheduler.send(:worker)).to be nil

        expect(scheduler).to have_attributes(
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
      before { scheduler.enabled = true }

      after { scheduler.terminate }

      it 'starts a worker thread' do
        allow(scheduler).to receive(:flush_events)

        perform

        expect(scheduler.send(:worker)).to be_a_kind_of(Thread)
        try_wait_until { scheduler.running? }

        expect(scheduler).to have_attributes(
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
    subject(:loop_back_off?) { scheduler.loop_back_off? }

    it { is_expected.to be false }
  end

  describe '#after_fork' do
    subject(:after_fork) { scheduler.after_fork }

    it 'clears the buffer' do
      expect(recorder).to receive(:flush)
      after_fork
    end
  end

  describe '#flush_and_wait' do
    subject(:flush_and_wait) { scheduler.send(:flush_and_wait) }

    let(:flush_time) { 0.05 }

    before do
      expect(scheduler).to receive(:flush_events) do
        sleep(flush_time)
      end
    end

    it 'changes its wait interval after flushing' do
      expect(scheduler).to receive(:loop_wait_time=) do |value|
        expected_interval = described_class::DEFAULT_INTERVAL_SECONDS - flush_time
        expect(value).to be <= expected_interval
      end

      flush_and_wait
    end

    context 'when the flush takes longer than an interval' do
      let(:options) { { **super(), interval: 0.01 } }

      # Assert that the interval isn't set below the min interval
      it "floors the wait interval to #{described_class::MIN_INTERVAL_SECONDS}" do
        expect(scheduler).to receive(:loop_wait_time=)
          .with(described_class::MIN_INTERVAL_SECONDS)

        flush_and_wait
      end
    end
  end

  describe '#flush_events' do
    subject(:flush_events) { scheduler.send(:flush_events) }

    let(:flush) { instance_double(Datadog::Profiling::Flush, event_count: event_count) }

    before { expect(recorder).to receive(:flush).and_return(flush) }

    context 'when no events are available' do
      let(:event_count) { 0 }

      it 'does not export' do
        exporters.each do |exporter|
          expect(exporter).to_not receive(:export)
        end

        is_expected.to be flush
      end
    end

    context 'when events are available' do
      let(:event_count) { 4 }

      context 'and all the exporters succeed' do
        it 'returns the flush' do
          expect(exporters).to all(receive(:export).with(flush))

          is_expected.to be flush
        end
      end

      context 'and one of the exporters fail' do
        before do
          allow(exporters.first).to receive(:export)
            .and_raise(StandardError)

          expect(Datadog.logger).to receive(:error)
            .with(/Unable to export \d+ profiling events/)
            .exactly(1).time
        end

        it 'returns the number of events flushed' do
          is_expected.to be flush

          expect(exporters).to all(have_received(:export).with(flush))
        end
      end
    end
  end

  describe '#loop_wait_before_first_iteration?' do
    it 'enables this feature of IntervalLoop' do
      expect(scheduler.loop_wait_before_first_iteration?).to be true
    end
  end

  describe '#work_pending?' do
    subject(:work_pending?) { scheduler.work_pending? }

    context 'when the recorder has no events' do
      before { expect(recorder).to receive(:empty?).and_return(true) }

      it { is_expected.to be false }
    end

    context 'when the recorder has events' do
      before { expect(recorder).to receive(:empty?).and_return(false) }

      it { is_expected.to be true }
    end
  end
end
