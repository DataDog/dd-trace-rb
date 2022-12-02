# typed: ignore

require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/cpu_and_wall_time_worker'

RSpec.describe Datadog::Profiling::Collectors::CpuAndWallTimeWorker do
  before { skip_if_profiling_not_supported(self) }

  let(:recorder) { Datadog::Profiling::StackRecorder.new }
  let(:gc_profiling_enabled) { true }
  let(:options) { {} }

  subject(:cpu_and_wall_time_worker) do
    described_class.new(
      recorder: recorder,
      max_frames: 400,
      tracer: nil,
      gc_profiling_enabled: gc_profiling_enabled,
      **options
    )
  end

  describe '.new' do
    it 'creates the garbage collection tracepoint in the disabled state' do
      expect(described_class::Testing._native_gc_tracepoint(cpu_and_wall_time_worker)).to_not be_enabled
    end
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

      another_instance = described_class.new(
        recorder: Datadog::Profiling::StackRecorder.new,
        max_frames: 400,
        tracer: nil,
        gc_profiling_enabled: gc_profiling_enabled,
      )
      another_instance.start

      exception = try_wait_until(backoff: 0.01) { another_instance.send(:failure_exception) }

      expect(exception.message).to include 'another instance'
    end

    it 'installs the profiling SIGPROF signal handler' do
      start

      expect(described_class::Testing._native_current_sigprof_signal_handler).to be :profiling
    end

    context 'when gc_profiling_enabled is true' do
      let(:gc_profiling_enabled) { true }

      it 'enables the garbage collection tracepoint' do
        start

        expect(described_class::Testing._native_gc_tracepoint(cpu_and_wall_time_worker)).to be_enabled
      end
    end

    context 'when gc_profiling_enabled is false' do
      let(:gc_profiling_enabled) { false }

      it 'does not enable the garbage collection tracepoint' do
        start

        expect(described_class::Testing._native_gc_tracepoint(cpu_and_wall_time_worker)).to_not be_enabled
      end
    end

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
      start

      all_samples = try_wait_until do
        samples = samples_from_pprof_without_gc(recorder.serialize!)
        samples if samples.any?
      end

      expect(samples_for_thread(all_samples, Thread.current)).to_not be_empty
    end

    it(
      'keeps statistics on how many samples were triggered by the background thread, ' \
      'as well as how many samples were requested from the VM'
    ) do
      start

      all_samples = try_wait_until do
        samples = samples_from_pprof_without_gc(recorder.serialize!)
        samples if samples.any?
      end

      cpu_and_wall_time_worker.stop

      sample_count =
        samples_for_thread(all_samples, Thread.current).map { |it| it.fetch(:values).fetch(:'cpu-samples') }.reduce(:+)

      stats = cpu_and_wall_time_worker.stats

      expect(sample_count).to be > 0
      expect(stats.fetch(:signal_handler_enqueued_sample)).to be >= sample_count
      expect(stats.fetch(:trigger_sample_attempts)).to be >= stats.fetch(:signal_handler_enqueued_sample)
    end

    it 'records garbage collection cycles' do
      if RUBY_VERSION.start_with?('3.')
        skip(
          'This test (and feature...) is broken on Ruby 3 if any Ractors get used due to a bug in the VM during ' \
          'Ractor GC, see https://bugs.ruby-lang.org/issues/19112 for details. ' \
          'For that reason, we disable this feature on Ruby 3 by default by passing `gc_profiling_enabled: false` during ' \
          'profiler initialization.'
        )
      end

      start

      described_class::Testing._native_trigger_sample

      invoke_gc_times = 5

      invoke_gc_times.times do
        Thread.pass
        GC.start
      end

      cpu_and_wall_time_worker.stop

      all_samples = samples_from_pprof(recorder.serialize!)

      current_thread_gc_samples =
        samples_for_thread(all_samples, Thread.current)
          .select { |it| it.fetch(:locations).first.fetch(:path) == 'Garbage Collection' }

      # NOTE: In some cases, Ruby may actually call two GC's back-to-back without us having the possibility to take
      # a sample. I don't expect this to happen for this test (that's what the `Thread.pass` above is trying to avoid)
      # but if this spec turns out to be flaky, that is probably the issue, and that would mean we'd need to relax the
      # check.
      expect(
        current_thread_gc_samples.inject(0) { |sum, sample| sum + sample.fetch(:values).fetch(:'cpu-samples') }
      ).to be >= invoke_gc_times
    end

    context 'when the background thread dies without cleaning up (after Ruby forks)' do
      it 'allows the CpuAndWallTimeWorker to be restarted' do
        start

        expect_in_fork do
          cpu_and_wall_time_worker.start
          wait_until_running
        end
      end

      it 'allows a different instance of the CpuAndWallTimeWorker to be started' do
        start

        expect_in_fork do
          another_instance = described_class.new(
            recorder: Datadog::Profiling::StackRecorder.new,
            max_frames: 400,
            tracer: nil,
            gc_profiling_enabled: gc_profiling_enabled,
          )
          another_instance.start

          try_wait_until(backoff: 0.01) { described_class::Testing._native_is_running?(another_instance) }
        end
      end

      it 'disables the existing gc_tracepoint before starting another CpuAndWallTimeWorker' do
        start

        expect_in_fork do
          another_instance = described_class.new(
            recorder: Datadog::Profiling::StackRecorder.new,
            max_frames: 400,
            tracer: nil,
            gc_profiling_enabled: gc_profiling_enabled,
          )
          another_instance.start

          try_wait_until(backoff: 0.01) { described_class::Testing._native_is_running?(another_instance) }

          expect(described_class::Testing._native_gc_tracepoint(cpu_and_wall_time_worker)).to_not be_enabled
          expect(described_class::Testing._native_gc_tracepoint(another_instance)).to be_enabled
        end
      end
    end

    context 'when main thread is sleeping but a background thread is working' do
      let(:ready_queue) { Queue.new }
      let(:background_thread) do
        Thread.new do
          ready_queue << true
          i = 0
          loop { (i = (i + 1) % 2) }
        end
      end

      after do
        background_thread.kill
        background_thread.join
      end

      it 'is able to sample even when the main thread is sleeping' do
        background_thread
        ready_queue.pop

        start
        wait_until_running

        sleep 0.1

        cpu_and_wall_time_worker.stop
        background_thread.kill

        result = samples_for_thread(samples_from_pprof_without_gc(recorder.serialize!), Thread.current)
        sample_count = result.map { |it| it.fetch(:values).fetch(:'cpu-samples') }.reduce(:+)

        stats = cpu_and_wall_time_worker.stats

        trigger_sample_attempts = stats.fetch(:trigger_sample_attempts)
        signal_handler_enqueued_sample = stats.fetch(:signal_handler_enqueued_sample)
        signal_handler_wrong_thread = stats.fetch(:signal_handler_wrong_thread)

        expect(signal_handler_enqueued_sample.to_f / trigger_sample_attempts).to (be >= 0.8), \
          "Expected at least 80% of signals to be delivered to correct thread (#{stats})"

        # Sanity checking

        # We're currently targeting 100 samples per second, so 5 in 100ms is a conservative approximation that hopefully
        # will not cause flakyness
        expect(sample_count).to be >= 5, "sample_count: #{sample_count}, stats: #{stats}"
        expect(trigger_sample_attempts).to be >= sample_count
        # It's possible that we stop in between trigger_sample_attempts being incrementing and the other values
        # actually being updated, so this is why we allow both values
        expect(
          [trigger_sample_attempts, trigger_sample_attempts - 1]
        ).to include(signal_handler_enqueued_sample + signal_handler_wrong_thread)
      end
    end

    context 'when all threads are sleeping (no thread holds the Global VM Lock)' do
      it 'is able to sample even when all threads are sleeping' do
        start
        wait_until_running

        sleep 0.1

        cpu_and_wall_time_worker.stop

        result = samples_for_thread(samples_from_pprof_without_gc(recorder.serialize!), Thread.current)
        sample_count = result.map { |it| it.fetch(:values).fetch(:'cpu-samples') }.reduce(:+)

        stats = cpu_and_wall_time_worker.stats

        trigger_sample_attempts = stats.fetch(:trigger_sample_attempts)
        signal_handler_enqueued_sample = stats.fetch(:signal_handler_enqueued_sample)
        signal_handler_wrong_thread = stats.fetch(:signal_handler_wrong_thread)

        simulated_signal_delivery = stats.fetch(:simulated_signal_delivery)

        expect(simulated_signal_delivery.to_f / trigger_sample_attempts).to (be >= 0.8), \
          "Expected at least 80% of signals to be simulated (#{stats})"

        # Sanity checking

        # We're currently targeting 100 samples per second, so 5 in 100ms is a conservative approximation that hopefully
        # will not cause flakyness
        expect(sample_count).to be >= 5, "sample_count: #{sample_count}, stats: #{stats}"
        expect(trigger_sample_attempts).to be >= sample_count
        # It's possible that we stop in between trigger_sample_attempts being incrementing and the other values
        # actually being updated, so this is why we allow both values
        expect(
          [trigger_sample_attempts, trigger_sample_attempts - 1]
        ).to include(signal_handler_enqueued_sample + signal_handler_wrong_thread)
      end
    end
  end

  describe 'Ractor safety' do
    before do
      skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION < '3.'

      # See native_extension_spec.rb for more details on the issues we saw on 3.0
      skip 'Ruby 3.0 Ractors are too buggy to run this spec' if RUBY_VERSION.start_with?('3.0.')
    end

    shared_examples_for 'does not trigger a sample' do |run_ractor|
      it 'does not trigger a sample' do
        cpu_and_wall_time_worker.start
        wait_until_running

        run_ractor.call

        cpu_and_wall_time_worker.stop

        samples_from_ractor =
          samples_from_pprof(recorder.serialize!)
            .select { |it| it.fetch(:labels)[:'thread name'] == 'background ractor' }

        expect(samples_from_ractor).to be_empty
      end
    end

    context 'when called from a background ractor' do
      # Even though we're not testing it explicitly, the GC profiling hooks can sometimes be called when running these
      # specs. Unfortunately, there's a VM crash in that case as well -- https://bugs.ruby-lang.org/issues/18464 --
      # so this must be disabled when interacting with Ractors.
      let(:gc_profiling_enabled) { false }

      describe 'handle_sampling_signal' do
        include_examples 'does not trigger a sample',
          (
            proc do
              Ractor.new do
                Thread.current.name = 'background ractor'
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker::Testing._native_simulate_handle_sampling_signal
              end.take
            end
          )
      end

      describe 'sample_from_postponed_job' do
        include_examples 'does not trigger a sample',
          (
            proc do
              Ractor.new do
                Thread.current.name = 'background ractor'
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker::Testing._native_simulate_sample_from_postponed_job
              end.take
            end
          )
      end

      # @ivoanjo: I initially tried to also test the GC callbacks, but it gets a bit hacky to force the thread
      # context creation for the ractors, and then simulate a GC. (For instance -- how to prevent against the context
      # creation running in parallel with a regular sample?)
    end
  end

  describe '#stop' do
    subject(:stop) { cpu_and_wall_time_worker.stop }

    context 'when called immediately after start' do
      it 'stops the CpuAndWallTimeWorker' do
        cpu_and_wall_time_worker.start

        stop

        expect(described_class::Testing._native_is_running?(cpu_and_wall_time_worker)).to be false
      end
    end

    context 'after starting' do
      before do
        cpu_and_wall_time_worker.start
        wait_until_running
      end

      it 'shuts down the background thread' do
        stop

        skip 'Spec not compatible with Ruby 2.2' if RUBY_VERSION.start_with?('2.2.')

        expect(Thread.list.map(&:name)).to_not include(described_class.name)
      end

      it 'replaces the profiling sigprof signal handler with an empty one' do
        stop

        expect(described_class::Testing._native_current_sigprof_signal_handler).to be :empty
      end

      it 'disables the garbage collection tracepoint' do
        stop

        expect(described_class::Testing._native_gc_tracepoint(cpu_and_wall_time_worker)).to_not be_enabled
      end

      it 'leaves behind an empty SIGPROF signal handler' do
        stop

        # Without an empty SIGPROF signal handler (e.g. with no signal handler) the following command will make the VM
        # instantly terminate with a confusing "Profiling timer expired" message left behind. (This message doesn't
        # come from us -- it's the default message for an unhandled SIGPROF. Pretty confusing UNIX/POSIX behavior...)
        Process.kill('SIGPROF', Process.pid)
      end
    end

    it 'unblocks SIGPROF signal handling from the worker thread' do
      inner_ran = false

      expect(described_class).to receive(:_native_sampling_loop).and_wrap_original do |native, *args|
        native.call(*args)

        expect(described_class::Testing._native_is_sigprof_blocked_in_current_thread).to be false
        inner_ran = true
      end

      cpu_and_wall_time_worker.start
      wait_until_running

      stop

      expect(inner_ran).to be true
    end
  end

  describe '#enabled=' do
    it 'does nothing (provided only for API compatibility)' do
      cpu_and_wall_time_worker.enabled = true
    end
  end

  describe '#reset_after_fork' do
    subject(:reset_after_fork) { cpu_and_wall_time_worker.reset_after_fork }

    let(:cpu_and_wall_time_collector) do
      Datadog::Profiling::Collectors::CpuAndWallTime.new(recorder: recorder, max_frames: 400, tracer: nil)
    end
    let(:options) { { cpu_and_wall_time_collector: cpu_and_wall_time_collector } }

    before do
      # This is important -- the real #reset_after_fork must not be called concurrently with the worker running,
      # which we do in this spec to make it easier to test the reset_after_fork behavior
      allow(cpu_and_wall_time_collector).to receive(:reset_after_fork)

      cpu_and_wall_time_worker.start
      wait_until_running
    end

    after do
      cpu_and_wall_time_worker.stop
    end

    it 'disables the gc_tracepoint' do
      expect { reset_after_fork }
        .to change { described_class::Testing._native_gc_tracepoint(cpu_and_wall_time_worker).enabled? }
        .from(true).to(false)
    end

    it 'resets the CpuAndWallTime collector only after disabling the tracepoint' do
      expect(cpu_and_wall_time_collector).to receive(:reset_after_fork) do
        expect(described_class::Testing._native_gc_tracepoint(cpu_and_wall_time_worker)).to_not be_enabled
      end

      reset_after_fork
    end

    it 'resets all stats' do
      cpu_and_wall_time_worker.stop

      reset_after_fork

      expect(cpu_and_wall_time_worker.stats.values).to all be 0
    end
  end

  def wait_until_running
    try_wait_until(backoff: 0.01) { described_class::Testing._native_is_running?(cpu_and_wall_time_worker) }
  end

  # This is useful because in a bunch of tests above we want to assert on properties of the period sampling, and having
  # a random GC in the middle of the spec contribute a sample can throw off the expected values and counts.
  #
  # We have separate specs that assert on the GC behaviors.
  def samples_from_pprof_without_gc(pprof_data)
    samples_from_pprof(pprof_data).reject { |it| it.fetch(:locations).first.fetch(:path) == 'Garbage Collection' }
  end
end
