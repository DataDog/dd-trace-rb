require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'datadog/profiling/profiler'

RSpec.describe Datadog::Profiling::Profiler do
  before { skip_if_profiling_not_supported(self) }

  subject(:profiler) { described_class.new(worker: worker, scheduler: scheduler) }

  let(:worker) { instance_double(Datadog::Profiling::Collectors::CpuAndWallTimeWorker) }
  let(:scheduler) { instance_double(Datadog::Profiling::Scheduler) }

  describe '#start' do
    subject(:start) { profiler.start }

    it 'signals collectors and scheduler to start' do
      expect(worker).to receive(:start)
      expect(scheduler).to receive(:start)

      start
    end

    context 'when called after a fork' do
      before { skip('Spec requires Ruby VM supporting fork') unless PlatformHelpers.supports_fork? }

      it 'resets the worker and the scheduler before starting them' do
        profiler # make sure instance is created in parent, so it detects the forking

        expect_in_fork do
          expect(worker).to receive(:reset_after_fork).ordered
          expect(scheduler).to receive(:reset_after_fork).ordered

          expect(worker).to receive(:start).ordered
          expect(scheduler).to receive(:start).ordered

          start
        end
      end
    end
  end

  describe '#shutdown!' do
    subject(:shutdown!) { profiler.shutdown! }

    it 'signals worker and scheduler to disable and stop' do
      expect(worker).to receive(:stop)

      expect(scheduler).to receive(:enabled=).with(false)
      expect(scheduler).to receive(:stop).with(true)

      shutdown!
    end
  end
end
