require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'datadog/profiling'
require 'datadog/profiling/profiler'
require 'datadog/profiling/collectors/old_stack'
require 'datadog/profiling/scheduler'

RSpec.describe Datadog::Profiling::Profiler do
  before { skip_if_profiling_not_supported(self) }

  subject(:profiler) { described_class.new(collectors, scheduler) }

  let(:collectors) { Array.new(2) { instance_double(Datadog::Profiling::Collectors::OldStack) } }
  let(:scheduler) { instance_double(Datadog::Profiling::Scheduler) }

  describe '::new' do
    it do
      is_expected.to have_attributes(
        collectors: collectors,
        scheduler: scheduler
      )
    end
  end

  describe '#start' do
    subject(:start) { profiler.start }

    it 'signals collectors and scheduler to start' do
      expect(collectors).to all(receive(:start))
      expect(scheduler).to receive(:start)

      start
    end

    context 'when called after a fork' do
      before { skip('Spec requires Ruby VM supporting fork') unless PlatformHelpers.supports_fork? }

      it 'resets the collectors and the scheduler before starting them' do
        profiler # make sure instance is created in parent, so it detects the forking

        expect_in_fork do
          expect(collectors).to all(receive(:reset_after_fork).ordered)
          expect(scheduler).to receive(:reset_after_fork).ordered

          expect(collectors).to all(receive(:start).ordered)
          expect(scheduler).to receive(:start).ordered

          start
        end
      end
    end
  end

  describe '#shutdown!' do
    subject(:shutdown!) { profiler.shutdown! }

    it 'signals collectors and scheduler to disable and stop' do
      expect(collectors).to all(receive(:enabled=).with(false))
      expect(collectors).to all(receive(:stop).with(true))

      expect(scheduler).to receive(:enabled=).with(false)
      expect(scheduler).to receive(:stop).with(true)

      shutdown!
    end
  end
end
