require "datadog/profiling/spec_helper"

require "datadog/profiling/scheduler"

RSpec.describe Datadog::Profiling::Scheduler do
  before { skip_if_profiling_not_supported(self) }

  let(:exporter) { instance_double(Datadog::Profiling::Exporter) }
  let(:transport) { instance_double(Datadog::Profiling::HttpTransport) }
  let(:interval) { 60 } # seconds
  let(:options) { {} }

  subject(:scheduler) { described_class.new(exporter: exporter, transport: transport, interval: interval, **options) }

  describe ".new" do
    describe "default settings" do
      it do
        is_expected.to have_attributes(
          enabled?: true,
          fork_policy: Datadog::Core::Workers::Async::Thread::FORK_POLICY_RESTART,
          loop_base_interval: 60, # seconds
        )
      end
    end
  end

  describe "#start" do
    subject(:start) { scheduler.start }

    it "starts the worker" do
      expect(scheduler).to receive(:perform)
      start
    end
  end

  describe "#perform" do
    subject(:perform) { scheduler.perform }

    after do
      scheduler.stop(true, 0)
      scheduler.join
    end

    context "when disabled" do
      before { scheduler.enabled = false }

      it "does not start a worker thread" do
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

    context "when enabled" do
      before { scheduler.enabled = true }

      after { scheduler.terminate }

      it "starts a worker thread" do
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

      context "when perform fails" do
        before { Thread.report_on_exception = false if Thread.respond_to?(:report_on_exception=) }
        after { Thread.report_on_exception = true if Thread.respond_to?(:report_on_exception=) }

        it "calls the on_failure_proc and logs the error" do
          expect(scheduler).to receive(:flush_and_wait).and_raise(StandardError.new("Simulated error"))

          # This is a bit ugly, but we want the logic in the background thread to be called immediately, and by
          # default we don't do that
          expect(scheduler).to receive(:loop_wait_before_first_iteration?).and_return(false)
          expect(scheduler).to receive(:work_pending?).and_return(true)

          allow(Datadog.logger).to receive(:debug)

          expect(Datadog.logger).to receive(:warn).with(/Profiling::Scheduler thread error/)

          proc_called = Queue.new

          scheduler.start(on_failure_proc: proc { proc_called << true })

          proc_called.pop
        end
      end

      context "when perform is interrupted" do
        it "logs the interruption" do
          inside_flush = Queue.new

          # This is a bit ugly, but we want the logic in the background thread to be called immediately, and by
          # default we don't do that
          expect(scheduler).to receive(:loop_wait_before_first_iteration?).and_return(false)
          expect(scheduler).to receive(:work_pending?).and_return(true)

          allow(Datadog.logger).to receive(:debug)
          expect(Datadog.logger).to receive(:debug).with(/#flush was interrupted or failed/)

          expect(scheduler).to receive(:flush_and_wait) do
            inside_flush << true
            sleep
          end

          scheduler.start
          inside_flush.pop

          scheduler.stop(true, 0)
          scheduler.join
        end
      end
    end
  end

  describe "#flush_and_wait" do
    subject(:flush_and_wait) { scheduler.send(:flush_and_wait) }

    let(:flush_time) { 0.05 }

    before do
      expect(scheduler).to receive(:flush_events) do
        sleep(flush_time)
      end
    end

    it "changes its wait interval after flushing" do
      expect(scheduler).to receive(:loop_wait_time=) do |value|
        expected_interval = interval - flush_time
        expect(value).to be <= expected_interval
      end

      flush_and_wait
    end

    context "when the flush takes longer than an interval" do
      let(:options) { {**super(), interval: 0.01} }

      # Assert that the interval isn't set below the min interval
      it "floors the wait interval to MINIMUM_INTERVAL_SECONDS" do
        expect(scheduler).to receive(:loop_wait_time=)
          .with(described_class.const_get(:MINIMUM_INTERVAL_SECONDS))

        flush_and_wait
      end
    end
  end

  describe "#flush_events" do
    subject(:flush_events) { scheduler.send(:flush_events) }

    let(:flush) { instance_double(Datadog::Profiling::Flush) }

    before { expect(exporter).to receive(:flush).and_return(flush) }

    it "exports the profiling data" do
      expect(transport).to receive(:export).with(flush)

      flush_events
    end

    context "when transport fails" do
      before do
        expect(transport).to receive(:export) { raise "Kaboom" }
      end

      it "gracefully handles the exception, logging it" do
        expect(Datadog.logger).to receive(:warn).with(/Kaboom/)
        expect(Datadog::Core::Telemetry::Logger).to receive(:report)
          .with(an_instance_of(RuntimeError), description: "Unable to report profile")

        flush_events
      end
    end

    context "when the flush does not contain enough data" do
      let(:flush) { nil }

      it "does not try to export the profiling data" do
        expect(transport).to_not receive(:export)

        flush_events
      end
    end

    context "when being run in a loop" do
      before { allow(scheduler).to receive(:run_loop?).and_return(true) }

      it "sleeps for up to DEFAULT_FLUSH_JITTER_MAXIMUM_SECONDS seconds before reporting" do
        expect(scheduler).to receive(:sleep) do |sleep_amount|
          expect(sleep_amount).to be < described_class.const_get(:DEFAULT_FLUSH_JITTER_MAXIMUM_SECONDS)
          expect(sleep_amount).to be_a_kind_of(Float)
          expect(transport).to receive(:export)
        end

        flush_events
      end
    end

    context "when being run as a one-off" do
      before { allow(scheduler).to receive(:run_loop?).and_return(false) }

      it "does not sleep before reporting" do
        expect(scheduler).to_not receive(:sleep)

        expect(transport).to receive(:export)

        flush_events
      end
    end
  end

  describe "#loop_wait_before_first_iteration?" do
    it "enables this feature of IntervalLoop" do
      expect(scheduler.loop_wait_before_first_iteration?).to be true
    end
  end

  describe "#work_pending?" do
    subject(:work_pending?) { scheduler.work_pending? }

    context "when the exporter can flush" do
      before { expect(exporter).to receive(:can_flush?).and_return(true) }

      it { is_expected.to be true }
    end

    context "when the exporter can not flush" do
      before { expect(exporter).to receive(:can_flush?).and_return(false) }

      it { is_expected.to be false }
    end

    context "when the profiler was marked as failed" do
      before do
        scheduler.mark_profiler_failed
        expect(exporter).to_not receive(:can_flush?)
      end

      it { is_expected.to be false }
    end
  end

  describe "#reset_after_fork" do
    subject(:reset_after_fork) { scheduler.reset_after_fork }

    it "resets the exporter" do
      expect(exporter).to receive(:reset_after_fork)

      reset_after_fork
    end
  end

  describe "#stop" do
    let(:flush) { instance_double(Datadog::Profiling::Flush) }
    let(:interval) { 1 }

    before { allow(transport).to receive(:export) }

    context "when exporter has data to flush" do
      before do
        allow(exporter).to receive(:can_flush?).and_return(true)
        allow(exporter).to receive(:flush).and_return(flush)
      end

      after do
        scheduler.stop(true) if instance_variable_defined?(:@stopped) && !@stopped
      end

      # This test validates the behavior of the @stop_requested flag.
      #
      # Specifically, the looping behavior we get from the core helpers will keep on trying to flush
      # while work_pending? is true. Because work_pending? used to keep on returning true while
      # exporter.can_flush? was true, this would cause the loop keep running.
      #
      # This was fixed by the introduction of @stop_requested, which ensures that we "remember"
      # when an export was done but a stop was requested.
      it "flushes the data and stops the loop" do
        scheduler.start
        wait_for { scheduler.run_loop? }.to be true

        @stopped = false
        expect(scheduler.stop(false, 10)).to be true
        @stopped = true
      end
    end
  end
end
