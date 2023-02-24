require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/idle_sampling_helper'

RSpec.describe Datadog::Profiling::Collectors::IdleSamplingHelper do
  before { skip_if_profiling_not_supported(self) }

  subject(:idle_sampling_helper) { described_class.new }

  describe '#start' do
    subject(:start) { idle_sampling_helper.start }

    after do
      idle_sampling_helper.stop
    end

    it 'resets the IdleSamplingHelper before creating a new thread' do
      expect(described_class).to receive(:_native_reset).with(idle_sampling_helper).ordered
      expect(Thread).to receive(:new).ordered

      start
    end

    it 'creates a new thread' do
      expect(Thread).to receive(:new)

      start
    end

    it 'does not create a second thread if start is called again' do
      start

      expect(Thread).to_not receive(:new)

      idle_sampling_helper.start
    end
  end

  describe '#stop' do
    subject(:stop) { idle_sampling_helper.stop }

    it 'shuts down the background thread' do
      worker_thread = idle_sampling_helper.instance_variable_get(:@worker_thread)

      stop

      expect(Thread.list).to_not include(worker_thread)
    end
  end

  describe 'idle_sampling_helper_request_action' do
    before { idle_sampling_helper.start }
    after { idle_sampling_helper.stop }

    # rubocop:disable Style/GlobalVars
    it 'runs the requested function in a background thread' do
      action_ran = Queue.new

      # idle_sampling_helper_request_action is built to be called from C code, not Ruby code, so the testing interface
      # is somewhat awkward and relies on a global variable
      $idle_sampling_helper_testing_action = proc do
        expect(Thread.current).to eq idle_sampling_helper.instance_variable_get(:@worker_thread)
        action_ran << true
      end

      described_class::Testing._native_idle_sampling_helper_request_action(idle_sampling_helper)

      action_ran.pop

      $idle_sampling_helper_testing_action = nil
    end
    # rubocop:enable Style/GlobalVars
  end
end
