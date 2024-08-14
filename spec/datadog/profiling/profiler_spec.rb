require "spec_helper"
require "datadog/profiling/spec_helper"

require "datadog/profiling/profiler"

RSpec.describe Datadog::Profiling::Profiler do
  before { skip_if_profiling_not_supported(self) }

  subject(:profiler) do
    described_class.new(worker: worker, scheduler: scheduler, optional_crashtracker: optional_crashtracker)
  end

  let(:worker) { instance_double(Datadog::Profiling::Collectors::CpuAndWallTimeWorker) }
  let(:scheduler) { instance_double(Datadog::Profiling::Scheduler) }
  let(:optional_crashtracker) { nil }

  describe "#start" do
    subject(:start) { profiler.start }

    it "signals the worker and scheduler to start" do
      expect(worker).to receive(:start).with(on_failure_proc: an_instance_of(Proc))
      expect(scheduler).to receive(:start).with(on_failure_proc: an_instance_of(Proc))

      start
    end

    context "when a crash tracker instance is provided" do
      let(:optional_crashtracker) { instance_double(Datadog::Profiling::Crashtracker) }

      it "signals the crash tracker to start before other components" do
        expect(optional_crashtracker).to receive(:start).ordered

        expect(worker).to receive(:start).ordered
        expect(scheduler).to receive(:start).ordered

        start
      end
    end

    context "when called after a fork" do
      before { skip("Spec requires Ruby VM supporting fork") unless PlatformHelpers.supports_fork? }

      it "resets the worker and the scheduler before starting them" do
        profiler # make sure instance is created in parent, so it detects the forking

        expect_in_fork do
          expect(worker).to receive(:reset_after_fork).ordered
          expect(scheduler).to receive(:reset_after_fork).ordered

          expect(worker).to receive(:start).ordered
          expect(scheduler).to receive(:start).ordered

          start
        end
      end

      context "when a crash tracker instance is provided" do
        let(:optional_crashtracker) { instance_double(Datadog::Profiling::Crashtracker) }

        it "resets the crash tracker before other coponents, as well as restarts it before other components" do
          profiler # make sure instance is created in parent, so it detects the forking

          expect_in_fork do
            expect(optional_crashtracker).to receive(:reset_after_fork).ordered
            expect(worker).to receive(:reset_after_fork).ordered
            expect(scheduler).to receive(:reset_after_fork).ordered

            expect(optional_crashtracker).to receive(:start).ordered
            expect(worker).to receive(:start).ordered
            expect(scheduler).to receive(:start).ordered

            start
          end
        end
      end
    end
  end

  describe "#shutdown!" do
    subject(:shutdown!) { profiler.shutdown! }

    it "signals worker and scheduler to disable and stop" do
      expect(worker).to receive(:stop)

      expect(scheduler).to receive(:enabled=).with(false)
      expect(scheduler).to receive(:stop).with(true)

      shutdown!
    end

    context "when a crash tracker instance is provided" do
      let(:optional_crashtracker) { instance_double(Datadog::Profiling::Crashtracker) }

      it "signals the crash tracker to stop, after other components have stopped" do
        expect(worker).to receive(:stop).ordered
        allow(scheduler).to receive(:enabled=)
        expect(scheduler).to receive(:stop).ordered

        expect(optional_crashtracker).to receive(:stop).ordered

        shutdown!
      end
    end
  end

  describe "Component failure handling" do
    let(:worker) { instance_double(Datadog::Profiling::Collectors::CpuAndWallTimeWorker, start: nil) }
    let(:scheduler) { instance_double(Datadog::Profiling::Scheduler, start: nil) }
    let(:optional_crashtracker) { instance_double(Datadog::Profiling::Crashtracker, start: nil) }

    before { allow(Datadog.logger).to receive(:warn) }

    context "when the worker failed" do
      let(:worker_on_failure) do
        on_failure = nil
        expect(worker).to receive(:start) { |on_failure_proc:| on_failure = on_failure_proc }

        profiler.start

        on_failure.call
      end

      before do
        allow(scheduler).to receive(:enabled=)
        allow(scheduler).to receive(:stop)
        allow(scheduler).to receive(:mark_profiler_failed)
      end

      it "logs the issue" do
        expect(Datadog.logger).to receive(:warn).with(/worker component/)

        worker_on_failure
      end

      it "marks the profiler as having failed in the scheduler" do
        expect(scheduler).to receive(:mark_profiler_failed)

        worker_on_failure
      end

      it "stops the scheduler" do
        expect(scheduler).to receive(:enabled=).with(false)
        expect(scheduler).to receive(:stop).with(true)

        worker_on_failure
      end

      it "does not stop the crashtracker" do
        expect(optional_crashtracker).to_not receive(:stop)

        worker_on_failure
      end
    end

    context "when the scheduler failed" do
      let(:scheduler_on_failure) do
        on_failure = nil
        expect(scheduler).to receive(:start) { |on_failure_proc:| on_failure = on_failure_proc }

        profiler.start

        on_failure.call
      end

      before do
        allow(worker).to receive(:stop)
      end

      it "logs the issue" do
        expect(Datadog.logger).to receive(:warn).with(/scheduler component/)

        scheduler_on_failure
      end

      it "stops the worker" do
        expect(worker).to receive(:stop)

        scheduler_on_failure
      end

      it "does not stop the crashtracker" do
        expect(optional_crashtracker).to_not receive(:stop)

        scheduler_on_failure
      end
    end

    context "when unknown component failed" do
      it "raises an ArgumentError" do
        expect { profiler.send(:component_failed, "test") }.to raise_error(ArgumentError, /failed_component: "test"/)
      end
    end
  end
end
