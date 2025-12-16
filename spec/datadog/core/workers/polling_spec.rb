require 'spec_helper'

require 'datadog/core/worker'
require 'datadog/core/workers/polling'

RSpec.describe Datadog::Core::Workers::Polling do
  context 'when included into a worker' do
    subject(:worker) { worker_class.new }

    let(:worker_class) do
      Class.new(Datadog::Core::Worker) { include Datadog::Core::Workers::Polling }
    end

    describe '#perform' do
      subject(:perform) { worker.perform }

      after { worker.stop(true, 5) }

      let(:worker) { worker_class.new(&task) }
      let(:task) { proc { |*args| worker_spy.perform(*args) } }
      let(:worker_spy) { double('worker spy') }

      before { allow(worker_spy).to receive(:perform) }

      context 'when #enabled? is true' do
        before { allow(worker).to receive(:enabled?).and_return(true) }

        it do
          perform
          wait_for(worker_spy).to have_received(:perform)
        end
      end

      context 'when #enabled? is false' do
        before { allow(worker).to receive(:enabled?).and_return(false) }

        it do
          perform
          expect(worker_spy).to_not have_received(:perform)
        end
      end
    end

    describe '#stop' do
      subject(:stop) { worker.stop }

      shared_context 'graceful stop' do
        before do
          allow(worker).to receive(:join)
            .with(described_class::DEFAULT_SHUTDOWN_TIMEOUT)
            .and_return(true)
        end
      end

      context 'when the worker has not been started' do
        before do
          allow(worker).to receive(:join)
            .with(described_class::DEFAULT_SHUTDOWN_TIMEOUT)
            .and_return(true)
        end

        it { is_expected.to be false }
      end

      context 'when the worker has been started' do
        include_context 'graceful stop'

        before do
          worker.perform
          try_wait_until { worker.running? && worker.run_loop? }
        end

        it { is_expected.to be true }
      end

      context 'when the worker has just been started' do
        # Set to true to assert on the state of the worker between operations.
        # Whehther these assertions are satisfied depends on how VM
        # schedules the threads. They are only useful if you are running
        # this test locally and in isolation, otherwise they are likely to
        # fail but this does not indicate a problem with the implementation,
        # just that the assertions are racy.
        let(:assert_racy_state) { false }

        # This is a regression test for a race condition, and as such
        # it may not always go through the same state sequence as the
        # original isssue.
        it 'stops the worker' do
          # Make sure the worker is not running.
          expect(worker.running?).to be false
          expect(worker.run_loop?).to be false

          # Start the worker. This creates a background thread and
          # schedules it to run, but at this point the background thread
          # has not yet executed any code.
          # I don't know of a way to assert that the thread has not
          # executed any code.
          worker.perform
          expect(worker.running?).to be true
          if assert_racy_state
            # run_loop? is false because @run_loop instance variable is
            # initialized by the background thread.
            #
            # On MRI, most of the time, the main thread will keep running
            # and the background thread won't have run anything yet, thus
            # these assertions will pass.
            # They will fail most of the time on JRuby which is truly
            # concurrent and will start the background thread running on
            # another core.
            expect(worker.run_loop?).to be false
            expect(worker.instance_variable_get('@run_loop')).to be nil
          end

          # Request the worker to stop.
          # This sets @run_loop to false.
          #
          # Call +stop_loop+ instead of +stop+ to assert that the stop
          # request does not change worker thread state immediately.
          # This is not (or should not be?) a public API though.
          # It's hard to test the race condition using sensible public APIs.
          #
          # The idea of the test is to stop the worker before it started,
          # but we cannot guarantee that the worker hasn't started yet.
          # Therefore, on some test runs, this test will pass (succeed)
          # without having done the desired operations and without passing
          # through the intended intermediate states.
          worker.stop_loop
          expect(worker.run_loop?).to be false
          if assert_racy_state
            # running? is still true because it looks at the liveness of
            # the background thread (which is still scheduled to run but
            # has not run).
            #
            # This assertion passes each time in my local testing even on
            # JRuby, but in theory the background thread can stop before
            # this check is performed.
            expect(worker.running?).to be true
          end

          # Wait for the thread to stop.
          try_wait_until { !worker.running? }
          Timeout.timeout(5) { worker.join }

          expect(worker.run_loop?).to be false
        end

        # The test is not guaranteed to exercise the intended
        # sequence of states on any given run. Run it a bunch of times
        # until it satisfies our desired state sequence.
        context 'when run several times' do
          # JRuby rarely attans the desired sequence of states,
          # but in my local testing succeeded with as few as 10 iteratons.
          # About 20 is typical.
          # There is generally no harm in having a large number here since
          # the test will stop once the desired conditions have been
          # achieved. The large number of iterations would only cause
          # an issue in CI (large test runtime) if for some reason the
          # scheduling is such that our desired state sequence literally
          # never happens.
          let(:iterations) { 1000 }

          it 'stops the worker on each iteration' do
            expected_state_met = false
            iterations_performed = 0

            iterations.times do |i|
              # Create a new worker instance for each iteration.
              worker = worker_class.new
              state_ok_1 = state_ok_2 = false

              # The rest of the test is the same as the single-iteration
              # annotated version above, except we track whether the
              # racy assertions are met.
              expect(worker.running?).to be false
              expect(worker.run_loop?).to be false

              worker.perform
              expect(worker.running?).to be true
              if !worker.run_loop? && worker.instance_variable_get('@run_loop').nil?
                state_ok_1 = true
              end

              worker.stop_loop
              expect(worker.run_loop?).to be false
              if worker.running?
                state_ok_2 = true
              end

              try_wait_until { !worker.running? }
              Timeout.timeout(5) { worker.join }

              expect(worker.run_loop?).to be false

              iterations_performed += 1

              if state_ok_1 && state_ok_2
                expected_state_met = true
                break
              end
            end

            expect(expected_state_met).to be true
            # Uncomment to see how many iterations were necessary to
            # achieve the desired conditions.
            #warn "took #{iterations_performed} iterations"
          end
        end
      end

      context 'called multiple times with graceful stop' do
        include_context 'graceful stop'

        before do
          worker.perform
          try_wait_until { worker.running? && worker.run_loop? }
        end

        it do
          expect(worker.stop).to be true
          try_wait_until { !worker.running? }
          expect(worker.stop).to be false
        end
      end

      context 'given force_stop: true' do
        subject(:stop) { worker.stop(true) }

        context 'and the worker does not gracefully stop' do
          before do
            # Make it ignore graceful stops
            allow(worker).to receive(:stop_loop).and_return(false)
            allow(worker).to receive(:join).and_return(nil)
          end

          context 'after the worker has been started' do
            before { worker.perform }

            it do
              is_expected.to be true

              # Give thread time to be terminated
              try_wait_until { !worker.running? }

              expect(worker.run_async?).to be false
              expect(worker.running?).to be false
            end
          end
        end
      end

      context 'given shutdown timeout' do
        subject(:stop) { worker.stop(false, 1000) }
        include_context 'graceful stop'

        before do
          expect(worker).to receive(:join)
            .with(1000)
            .and_return(true)

          worker.perform
          try_wait_until { worker.running? && worker.run_loop? }
        end

        it { is_expected.to be true }
      end
    end

    describe '#enabled?' do
      subject(:enabled?) { worker.enabled? }

      before { allow(worker).to receive(:perform) }

      context 'by default' do
        it { is_expected.to be true }
      end

      context 'when enabled= is set to false' do
        it do
          expect { worker.enabled = false }
            .to change { worker.enabled? }
            .from(true)
            .to(false)
        end
      end
    end

    describe '#enabled=' do
      subject(:set_enabled_value) { worker.enabled = value }

      context 'and given true' do
        let(:value) { true }

        it do
          expect { set_enabled_value }
            .to_not change { worker.enabled? }
            .from(true)
        end
      end

      context 'and given false' do
        let(:value) { false }

        it do
          expect { set_enabled_value }
            .to change { worker.enabled? }
            .from(true)
            .to(false)
        end
      end

      context 'and given nil' do
        let(:value) { nil }

        it 'does nothing' do
          expect { set_enabled_value }
            .to change { worker.enabled? }
            .from(true)
            .to(false)
        end
      end
    end
  end
end
