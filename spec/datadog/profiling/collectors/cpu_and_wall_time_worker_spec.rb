# typed: ignore

require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/cpu_and_wall_time_worker'

RSpec.describe Datadog::Profiling::Collectors::CpuAndWallTimeWorker do
  before { skip_if_profiling_not_supported(self) }

  let(:recorder) { Datadog::Profiling::StackRecorder.new }

  subject(:cpu_and_wall_time_worker) { described_class.new(recorder: recorder, max_frames: 400) }

  describe '.new' do
    it 'creates the garbage collection tracepoint in the disabled state'
  end

  describe '#start' do
    subject(:start) do
      cpu_and_wall_time_worker.start
      wait_until_running
    end

    after do
      cpu_and_wall_time_worker.stop
    end

    it 'creates a new thread' do
      skip 'Spec not compatible with Ruby 2.2' if RUBY_VERSION.start_with?('2.2.')

      start

      expect(Thread.list.map(&:name)).to include(described_class.name)
    end

    it 'does not create a second thread if start is called again' do
      start

      expect(Thread).to_not receive(:new)

      cpu_and_wall_time_worker.start
    end

    it 'does not allow other instances of the CpuAndWallTimeWorker to start' do
      start

      allow(Datadog.logger).to receive(:warn)

      another_instance = described_class.new(recorder: Datadog::Profiling::StackRecorder.new, max_frames: 400)
      another_instance.start

      exception = try_wait_until(backoff: 0.01) { another_instance.send(:failure_exception) }

      expect(exception.message).to include 'another instance'
    end

    it 'installs the profiling SIGPROF signal handler' do
      start

      expect(described_class::Testing._native_current_sigprof_signal_handler).to be :profiling
    end

    it 'enables the garbage collection tracepoint'

    context 'when a previous signal handler existed' do
      before do
        described_class::Testing._native_install_testing_signal_handler
        expect(described_class::Testing._native_current_sigprof_signal_handler).to be :other

        allow(Datadog.logger).to receive(:warn)
      end

      after do
        described_class::Testing._native_remove_testing_signal_handler
      end

      it 'does not start the sampling loop' do
        cpu_and_wall_time_worker.start

        exception = try_wait_until(backoff: 0.01) { cpu_and_wall_time_worker.send(:failure_exception) }

        expect(exception.message).to include 'pre-existing SIGPROF'
      end

      it 'leaves the existing signal handler in place' do
        cpu_and_wall_time_worker.start

        try_wait_until(backoff: 0.01) { cpu_and_wall_time_worker.send(:failure_exception) }

        expect(described_class::Testing._native_current_sigprof_signal_handler).to be :other
      end
    end

    it 'triggers sampling and records the results' do
      pending 'Currently broken on Ruby 2.2 due to missing ruby_thread_has_gvl_p API' if RUBY_VERSION.start_with?('2.2.')

      start

      all_samples = try_wait_until do
        serialization_result = recorder.serialize
        raise 'Unexpected: Serialization failed' unless serialization_result

        samples = samples_from_pprof(serialization_result.last)
        samples if samples.any?
      end

      current_thread_sample = all_samples.find do |it|
        it.fetch(:labels).fetch(:'thread id') == Thread.current.object_id.to_s
      end

      expect(current_thread_sample).to_not be nil
    end
  end

  describe '#stop' do
    subject(:stop) { cpu_and_wall_time_worker.stop }

    before do
      cpu_and_wall_time_worker.start
      wait_until_running
    end

    it 'shuts down the background thread' do
      stop

      skip 'Spec not compatible with Ruby 2.2' if RUBY_VERSION.start_with?('2.2.')

      expect(Thread.list.map(&:name)).to_not include(described_class.name)
    end

    it 'removes the profiling sigprof signal handler' do
      stop

      expect(described_class::Testing._native_current_sigprof_signal_handler).to be nil
    end

    it 'disables the garbage collection tracepoint'
  end

  describe '#enabled=' do
    it 'does nothing (provided only for API compatibility)' do
      cpu_and_wall_time_worker.enabled = true
    end
  end

  def wait_until_running
    try_wait_until(backoff: 0.01) { described_class::Testing._native_is_running?(cpu_and_wall_time_worker) }
  end
end
