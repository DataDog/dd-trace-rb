require 'spec_helper'

require 'datadog/profiling/http_transport'
require 'datadog/profiling/exporter'
require 'datadog/profiling/scheduler'

RSpec.describe Datadog::Profiling::Scheduler do
  subject(:scheduler) { described_class.new(exporter: exporter, transport: transport, **options) }

  let(:exporter) { instance_double(Datadog::Profiling::Exporter) }
  let(:transport) { instance_double(Datadog::Profiling::HttpTransport) }
  let(:options) { {} }

  describe '.new' do
    describe 'default settings' do
      it do
        is_expected.to have_attributes(
          enabled?: true,
          fork_policy: Datadog::Core::Workers::Async::Thread::FORK_POLICY_RESTART,
          loop_base_interval: 60, # seconds
        )
      end
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
        expected_interval = described_class.const_get(:DEFAULT_INTERVAL_SECONDS) - flush_time
        expect(value).to be <= expected_interval
      end

      flush_and_wait
    end

    context 'when the flush takes longer than an interval' do
      let(:options) { { **super(), interval: 0.01 } }

      # Assert that the interval isn't set below the min interval
      it "floors the wait interval to #{described_class.const_get(:MINIMUM_INTERVAL_SECONDS)}" do
        expect(scheduler).to receive(:loop_wait_time=)
          .with(described_class.const_get(:MINIMUM_INTERVAL_SECONDS))

        flush_and_wait
      end
    end
  end

  describe '#flush_events' do
    subject(:flush_events) { scheduler.send(:flush_events) }

    let(:flush) { instance_double(Datadog::Profiling::Flush) }

    before { expect(exporter).to receive(:flush).and_return(flush) }

    it 'exports the profiling data' do
      expect(transport).to receive(:export).with(flush)

      flush_events
    end

    context 'when transport fails' do
      before do
        expect(transport).to receive(:export) { raise 'Kaboom' }
      end

      it 'gracefully handles the exception, logging it' do
        expect(Datadog.logger).to receive(:error).with(/Kaboom/)

        flush_events
      end
    end

    context 'when the flush does not contain enough data' do
      let(:flush) { nil }

      it 'does not try to export the profiling data' do
        expect(transport).to_not receive(:export)

        flush_events
      end
    end

    context 'when being run in a loop' do
      before { allow(scheduler).to receive(:run_loop?).and_return(true) }

      it 'sleeps for up to DEFAULT_FLUSH_JITTER_MAXIMUM_SECONDS seconds before reporting' do
        expect(scheduler).to receive(:sleep) do |sleep_amount|
          expect(sleep_amount).to be < described_class.const_get(:DEFAULT_FLUSH_JITTER_MAXIMUM_SECONDS)
          expect(sleep_amount).to be_a_kind_of(Float)
          expect(transport).to receive(:export)
        end

        flush_events
      end
    end

    context 'when being run as a one-off' do
      before { allow(scheduler).to receive(:run_loop?).and_return(false) }

      it 'does not sleep before reporting' do
        expect(scheduler).to_not receive(:sleep)

        expect(transport).to receive(:export)

        flush_events
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

    context 'when the exporter can flush' do
      before { expect(exporter).to receive(:can_flush?).and_return(true) }

      it { is_expected.to be true }
    end

    context 'when the exporter can not flush' do
      before { expect(exporter).to receive(:can_flush?).and_return(false) }

      it { is_expected.to be false }
    end
  end

  describe '#reset_after_fork' do
    subject(:reset_after_fork) { scheduler.reset_after_fork }

    it 'resets the exporter' do
      expect(exporter).to receive(:reset_after_fork)

      reset_after_fork
    end
  end
end
