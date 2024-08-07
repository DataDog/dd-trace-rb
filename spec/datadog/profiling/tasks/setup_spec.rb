require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'datadog/profiling'
require 'datadog/profiling/tasks/setup'
require 'datadog/profiling/ext/forking'

RSpec.describe Datadog::Profiling::Tasks::Setup do
  subject(:task) { described_class.new }

  describe '#run' do
    subject(:run) { task.run }

    before do
      described_class::ACTIVATE_EXTENSIONS_ONLY_ONCE.send(:reset_ran_once_state_for_tests)
    end

    it 'actives the forking extension before setting up the at_fork hooks' do
      expect(task).to receive(:activate_forking_extensions).ordered
      expect(task).to receive(:setup_at_fork_hooks).ordered

      run
    end

    it 'only sets up the extensions and hooks once, even across different instances' do
      expect_any_instance_of(described_class).to receive(:activate_forking_extensions).once
      expect_any_instance_of(described_class).to receive(:setup_at_fork_hooks).once

      task.run
      task.run
      described_class.new.run
      described_class.new.run
    end
  end

  describe '#activate_forking_extensions' do
    subject(:activate_forking_extensions) { task.send(:activate_forking_extensions) }

    context 'when forking extensions are supported' do
      before do
        allow(Datadog::Profiling::Ext::Forking)
          .to receive(:supported?)
          .and_return(true)
      end

      context 'and succeeds' do
        it 'applies forking extensions' do
          expect(Datadog::Profiling::Ext::Forking).to receive(:apply!)
          expect(Datadog.logger).to_not receive(:warn)
          activate_forking_extensions
        end
      end

      context 'but fails' do
        before do
          expect(Datadog::Profiling::Ext::Forking)
            .to receive(:apply!)
            .and_raise(StandardError)
        end

        it 'logs a warning' do
          expect(Datadog.logger).to receive(:warn) do |&message|
            expect(message.call).to include('forking extensions unavailable')
          end

          activate_forking_extensions
        end
      end
    end

    context 'when forking extensions are not supported' do
      before do
        allow(Datadog::Profiling::Ext::Forking)
          .to receive(:supported?)
          .and_return(false)
      end

      context 'and profiling is enabled' do
        before do
          allow(Datadog.configuration.profiling)
            .to receive(:enabled)
            .and_return(true)
        end

        it 'skips forking extensions with warning' do
          expect(Datadog::Profiling::Ext::Forking).to_not receive(:apply!)
          expect(Datadog.logger).to receive(:debug) do |message|
            expect(message).to include('forking extensions skipped')
          end

          activate_forking_extensions
        end
      end

      context 'and profiling is disabled' do
        before do
          allow(Datadog.configuration.profiling)
            .to receive(:enabled)
            .and_return(false)
        end

        it 'skips forking extensions without warning' do
          expect(Datadog::Profiling::Ext::Forking).to_not receive(:apply!)
          expect(Datadog.logger).to_not receive(:debug)
          activate_forking_extensions
        end
      end
    end
  end

  describe '#setup_at_fork_hooks' do
    subject(:setup_at_fork_hooks) { task.send(:setup_at_fork_hooks) }

    context 'when Process#datadog_at_fork is available' do
      before do
        allow(Process).to receive(:respond_to?).with(:datadog_at_fork).and_return(true)
        allow(Datadog::Profiling).to receive(:start_if_enabled)

        without_partial_double_verification do
          allow(Process).to receive(:datadog_at_fork)
        end
      end

      let(:at_fork_hook) do
        the_hook = nil

        without_partial_double_verification do
          expect(Process).to receive(:datadog_at_fork).with(:child) do |&block|
            the_hook = block
          end
        end

        setup_at_fork_hooks

        the_hook
      end

      it 'sets up an at_fork hook that restarts the profiler' do
        expect(Datadog::Profiling).to receive(:start_if_enabled)

        at_fork_hook.call
      end

      context 'when there is an issue starting the profiler' do
        before do
          expect(Datadog::Profiling).to receive(:start_if_enabled).and_raise('Dummy exception')
          allow(Datadog.logger).to receive(:warn) # Silence logging during tests
        end

        it 'does not raise any error' do
          at_fork_hook.call
        end

        it 'logs an exception' do
          expect(Datadog.logger).to receive(:warn) do |&message|
            expect(message.call).to include('Dummy exception')
          end

          at_fork_hook.call
        end
      end
    end

    context 'when #datadog_at_fork is not available' do
      before do
        allow(Process).to receive(:respond_to?).with(:datadog_at_fork).and_return(false)
      end

      it 'does nothing' do
        without_partial_double_verification do
          expect(Process).to_not receive(:datadog_at_fork)

          setup_at_fork_hooks
        end
      end
    end
  end
end
