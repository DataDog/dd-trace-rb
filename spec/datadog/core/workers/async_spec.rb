require 'spec_helper'

require 'datadog/core/worker'
require 'datadog/core/workers/async'

RSpec.describe Datadog::Core::Workers::Async::Thread do
  context 'when included into a worker' do
    subject(:worker) { worker_class.new(&task) }

    let(:worker_class) do
      Class.new(Datadog::Core::Worker) { include Datadog::Core::Workers::Async::Thread }
    end

    let(:task) { proc { |*args| worker_spy.perform(*args) } }
    let(:worker_spy) { double('worker spy') }

    before { allow(worker_spy).to receive(:perform) }

    after do
      thread = worker.send(:worker)
      if thread
        # Avoid tripping RSpec expectations on the worker thread
        # when calling `terminate` and `join` below.
        RSpec::Mocks.space.proxy_for(thread).reset

        thread.terminate
        begin
          thread.join
        rescue error_class => _e
          # Prevents test from erroring out during cleanup
        end
      end
    end

    shared_context 'perform and wait' do
      let(:perform) { worker.perform(*args) }
      let(:args) { [:foo, :bar] }
      let(:perform_complete) { ConditionVariable.new }
      let(:perform_result) { double('perform result') }
      let(:perform_task) { proc { |*_args| } }

      before do
        allow(worker_spy).to receive(:perform) do |*actual_args|
          perform_task.call(*actual_args)
          perform_complete.signal
          perform_result
        end

        perform

        # Block until #perform gives signal or timeout is reached.
        Mutex.new.tap do |mutex|
          mutex.synchronize do
            perform_complete.wait(mutex, 0.1)
            sleep(0.1) # Give a little extra time to collect the thread.
          end
        end
      end
    end

    shared_context 'perform and wait with error' do
      include_context 'perform and wait' do
        let(:error) { error_class.new }
        let(:error_class) { stub_const('TestError', Class.new(StandardError)) }
        let(:perform_task) do
          proc do |*_actual_args|
            # Silence "Thread terminated with exception" Ruby logs for this worker thread, since we're deliberately
            # letting the thread fail with an exception
            Thread.current.report_on_exception = false if Thread.current.respond_to?(:report_on_exception=)

            raise error
          end
        end
      end
    end

    describe '#perform' do
      subject(:perform) { worker.perform(*args) }

      let(:args) { [:foo, :bar] }

      context 'given arguments' do
        include_context 'perform and wait' do
          let(:perform_task) do
            proc do |*actual_args|
              expect(actual_args).to eq args
            end
          end
        end

        it 'performs the task async' do
          expect(worker.result).to eq(perform_result)
          expect(worker).to have_attributes(
            result: perform_result,
            error?: false,
            error: nil,
            completed?: true,
            started?: true,
            run_async?: true
          )
        end

        it 'returns nil' do
          expect(perform).to be nil
        end
      end
    end

    describe '#error?' do
      subject(:error?) { worker.error? }

      context 'by default' do
        it { is_expected.to be false }
      end

      context 'when #perform raises an error' do
        include_context 'perform and wait with error'
        it { is_expected.to be true }
      end
    end

    describe '#error' do
      subject(:error) { worker.error }

      context 'by default' do
        it { is_expected.to be nil }
      end

      context 'when #perform raises an error' do
        include_context 'perform and wait with error'
        it { is_expected.to be error }
      end
    end

    describe '#result' do
      subject(:result) { worker.result }

      context 'by default' do
        it { is_expected.to be nil }
      end

      context 'after #perform completes' do
        include_context 'perform and wait'
        it { is_expected.to be perform_result }
      end
    end

    describe '#fork_policy' do
      subject(:fork_policy) { worker.fork_policy }

      context 'by default' do
        it { is_expected.to be described_class::FORK_POLICY_STOP }
      end

      context 'when set' do
        let(:policy) { double('policy') }

        it do
          expect { worker.fork_policy = policy }
            .to change { worker.fork_policy }
            .from(described_class::FORK_POLICY_STOP)
            .to(policy)
        end
      end
    end

    describe '#fork_policy=' do
      subject(:set_fork_policy) { worker.fork_policy = policy }

      let(:policy) { double('policy') }

      it do
        expect { set_fork_policy }
          .to change { worker.fork_policy }
          .from(described_class::FORK_POLICY_STOP)
          .to(policy)
      end
    end

    describe '#join' do
      subject(:join) { worker.join }

      let(:thread) { worker.send(:worker) }

      context 'when not started' do
        it { is_expected.to be true }
      end

      context 'when started' do
        let(:task) { proc { sleep(0.1) } }
        let(:join_result) { double('join result') }

        before do
          worker.perform

          expect(thread).to receive(:join)
            .with(timeout).and_call_original
        end

        context 'given no arguments' do
          let(:timeout) { nil }

          it { is_expected.to be true }
        end

        context 'given a timeout' do
          subject(:join) { worker.join(timeout) }

          context 'which is not reached' do
            let(:timeout) { 10 }

            it { is_expected.to be true }
          end

          context 'which is reached' do
            let(:timeout) { 0 }

            it { is_expected.to be false }
          end
        end
      end
    end

    describe '#terminate' do
      subject(:terminate) { worker.terminate }

      context 'when not started' do
        it { is_expected.to be false }
      end

      context 'when started' do
        let(:task) { proc { sleep(1) } }
        let(:join_result) { double('join result') }

        before do
          worker.perform
          expect(worker.send(:worker)).to receive(:terminate)
            .and_call_original
        end

        it do
          is_expected.to be true
          expect(worker.run_async?).to be false
        end
      end
    end

    describe '#run_async?' do
      subject(:run_async?) { worker.run_async? }

      context 'by default' do
        it { is_expected.to be false }
      end

      context 'when started' do
        before { worker.perform }

        it { is_expected.to be true }
      end
    end

    describe '#started?' do
      subject(:started?) { worker.started? }

      context 'by default' do
        it { is_expected.to be false }
      end

      context 'when started' do
        before { worker.perform }

        it { is_expected.to be true }
      end
    end

    describe '#running?' do
      subject(:running?) { worker.running? }

      before { allow(worker_spy).to(receive(:perform)) { sleep 5 } }

      context 'by default' do
        it { is_expected.to be false }
      end

      context 'when started' do
        before do
          worker.perform
          try_wait_until { worker.running? }
        end

        it { is_expected.to be true }
      end
    end

    describe '#completed?' do
      subject(:completed?) { worker.completed? }

      context 'by default' do
        it { is_expected.to be false }
      end

      context 'when running' do
        let(:task) { proc { sleep(1) } }

        before do
          worker.perform
          try_wait_until { worker.running? }
        end

        it do
          expect(worker.running?).to be true
          is_expected.to be false
        end
      end

      context 'when completed successfully' do
        include_context 'perform and wait'
        it { is_expected.to be true }
      end

      context 'when failed' do
        include_context 'perform and wait with error'
        it { is_expected.to be false }
      end
    end

    describe '#failed?' do
      subject(:failed?) { worker.failed? }

      context 'by default' do
        it { is_expected.to be false }
      end

      context 'when running' do
        let(:task) { proc { sleep(1) } }

        before { worker.perform }

        it do
          expect(worker.running?).to be true
          is_expected.to be false
        end
      end

      context 'when completed successfully' do
        include_context 'perform and wait'
        it { is_expected.to be false }
      end

      context 'when failed' do
        include_context 'perform and wait with error'

        it do
          is_expected.to be true
          expect(worker.error?).to be true
        end
      end
    end

    describe '#forked?' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      subject(:forked?) { worker.forked? }

      context 'by default' do
        it { is_expected.to be false }
      end

      context 'when started but not forked' do
        let(:task) { proc { sleep(1) } }

        before { worker.perform }

        it do
          expect(worker.running?).to be true
          is_expected.to be false
        end
      end

      context 'when started then forked' do
        let(:task) { proc { sleep(1) } }

        before { worker.perform }

        it do
          expect(worker.running?).to be true
          expect(worker.forked?).to be false

          expect_in_fork do
            expect(worker.forked?).to be true
          end
        end
      end
    end

    describe 'integration tests' do
      describe 'forking' do
        before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

        context 'when the process forks' do
          context 'with FORK_POLICY_STOP fork policy' do
            before { worker.fork_policy = described_class::FORK_POLICY_STOP }

            it 'does not restart the worker' do
              worker.perform

              expect_in_fork do
                expect(worker.running?).to be false

                # Capture the flush
                @performed = false
                allow(worker_spy).to receive(:perform) do
                  @performed = true
                end

                # Attempt restart of worker & verify it stops.
                expect { worker.perform }.to change { worker.run_async? }
                  .from(true)
                  .to(false)
              end
            end
          end

          context 'with FORK_POLICY_RESTART fork policy' do
            before { worker.fork_policy = described_class::FORK_POLICY_RESTART }

            it 'restarts the worker' do
              # Start worker
              worker.perform

              expect_in_fork do
                expect(worker.running?).to be false

                # Capture the flush
                @performed = false
                allow(worker_spy).to receive(:perform) do
                  @performed = true
                end

                # Restart worker & wait
                worker.perform
                try_wait_until { @performed }

                # Verify state of the worker
                expect(worker.failed?).to be false
                expect(worker_spy).to have_received(:perform).at_least(:once)
              end
            end
          end
        end
      end
    end

    describe 'thread naming' do
      after { worker.terminate }

      context 'on Ruby < 2.3' do
        before do
          skip 'Only applies to old Rubies' if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.3')
        end

        it 'does not try to set a thread name' do
          without_partial_double_verification do
            expect_any_instance_of(Thread).not_to receive(:name=)
          end

          worker.perform
        end
      end

      context 'on Ruby >= 2.3' do
        before do
          skip 'Not supported on old Rubies' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3')
        end

        let(:worker_class) do
          stub_const(
            'AsyncSpecThreadNaming',
            Class.new(Datadog::Core::Worker) do
              include Datadog::Core::Workers::Async::Thread
            end
          )
        end

        it 'sets the name of the created thread to match the worker class name' do
          worker.perform

          expect(worker.send(:worker).name).to eq worker_class.to_s
        end
      end
    end
  end
end
