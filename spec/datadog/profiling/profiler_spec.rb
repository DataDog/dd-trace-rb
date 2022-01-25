# typed: false
require 'spec_helper'

require 'datadog/profiling'
require 'datadog/profiling/profiler'

RSpec.describe Datadog::Profiling::Profiler do
  subject(:profiler) { described_class.new(collectors, scheduler) }

  let(:collectors) { Array.new(2) { instance_double(Datadog::Profiling::Collectors::Stack) } }
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
