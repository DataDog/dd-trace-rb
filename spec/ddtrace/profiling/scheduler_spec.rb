require 'spec_helper'

require 'ddtrace/profiling/exporter'
require 'ddtrace/profiling/recorder'
require 'ddtrace/profiling/scheduler'

RSpec.describe Datadog::Profiling::Scheduler do
  subject(:scheduler) { described_class.new(recorder, exporters, options) }
  let(:recorder) { instance_double(Datadog::Profiling::Recorder) }
  let(:exporters) { [instance_double(Datadog::Profiling::Exporter)] }
  let(:options) { {} }

  describe '::new' do
    it 'with default settings' do
      is_expected.to have_attributes(
        enabled?: false,
        exporters: exporters,
        fork_policy: Datadog::Workers::Async::Thread::FORK_POLICY_RESTART,
        loop_base_interval: described_class::DEFAULT_INTERVAL,
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
    after { scheduler.stop(true, 0) }

    context 'when disabled' do
      before { scheduler.enabled = false }

      it 'does not start a worker thread' do
        is_expected.to be nil

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

      it 'starts a worker thread' do
        allow(scheduler).to receive(:flush_events)

        is_expected.to be_a_kind_of(Thread)
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
      expect(recorder).to receive(:pop)
      after_fork
    end
  end

  describe '#flush_and_wait' do
    subject(:flush_and_wait) { scheduler.flush_and_wait }
    let(:flush_time) { 0.05 }

    before do
      expect(scheduler).to receive(:flush_events) do
        sleep(flush_time)
      end
    end

    it 'changes its wait interval after flushing' do
      expect(scheduler).to receive(:loop_wait_time=) do |value|
        expected_interval = described_class::DEFAULT_INTERVAL - flush_time
        expect(value).to be <= expected_interval
      end

      flush_and_wait
    end

    context 'when the flush takes longer than an interval' do
      let(:options) { { interval: 0.01 } }

      # Assert that the interval isn't set below the min interval
      it "floors the wait interval to #{described_class::MIN_INTERVAL}" do
        expect(scheduler).to receive(:loop_wait_time=)
          .with(described_class::MIN_INTERVAL)

        flush_and_wait
      end
    end
  end

  describe '#flush_events' do
    subject(:flush_events) { scheduler.flush_events }

    before do
      expect(recorder).to receive(:pop).and_return(flushes)
      exporters.each { |exporter| allow(exporter).to receive(:export) }
    end

    context 'when no flushes are available' do
      let(:flushes) { [] }

      it 'does not export' do
        is_expected.to be 0

        exporters.each do |exporter|
          expect(exporter).to_not have_received(:export)
        end
      end
    end

    context 'when flushes are available' do
      let(:flushes) do
        [
          instance_double(
            Datadog::Profiling::Flush,
            event_class: double('event class'),
            events: Array.new(2) { double('event') }
          ),
          instance_double(
            Datadog::Profiling::Flush,
            event_class: double('event class'),
            events: Array.new(2) { double('event') }
          )
        ]
      end

      let(:total_num_events) { flushes.inject(0) { |sum, f| sum + f.events.length } }

      context 'and all the exporters succeed' do
        it 'returns the number of events flushed' do
          is_expected.to eq(total_num_events)

          exporters.each do |exporter|
            expect(exporter)
              .to have_received(:export)
              .with(flushes)
          end
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
          is_expected.to eq(total_num_events)

          exporters.each do |exporter|
            expect(exporter)
              .to have_received(:export)
              .with(flushes)
          end
        end
      end
    end
  end
end
