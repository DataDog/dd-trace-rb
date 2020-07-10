require 'spec_helper'

require 'ddtrace/profiling'
require 'ddtrace/profiling/profiler'

RSpec.describe Datadog::Profiler do
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
      collectors.each { |c| expect(c).to receive(:start) }
      expect(scheduler).to receive(:start)
      start
    end
  end

  describe '#shutdown!' do
    subject(:shutdown!) { profiler.shutdown! }
    it 'signals collectors and scheduler to disable and stop' do
      collectors.each do |c|
        expect(c).to receive(:enabled=).with(false)
        expect(c).to receive(:stop).with(true)
      end

      expect(scheduler).to receive(:enabled=).with(false)
      expect(scheduler).to receive(:stop).with(true)

      shutdown!
    end
  end
end
