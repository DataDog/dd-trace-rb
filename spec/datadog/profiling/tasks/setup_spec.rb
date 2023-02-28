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

      allow(task).to receive(:check_if_cpu_time_profiling_is_supported)
    end

    it 'actives the forking extension before setting up the at_fork hooks' do
      expect(task).to receive(:activate_forking_extensions).ordered
      expect(task).to receive(:setup_at_fork_hooks).ordered

      run
    end

    it 'checks if CPU time profiling is available' do
      expect(task).to receive(:check_if_cpu_time_profiling_is_supported)

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

  describe '#check_if_cpu_time_profiling_is_supported' do
    subject(:check_if_cpu_time_profiling_is_supported) { task.send(:check_if_cpu_time_profiling_is_supported) }

    before do
      expect(task).to receive(:cpu_time_profiling_unsupported_reason).and_return(unsupported_reason)
    end

    context 'when CPU time profiling is supported' do
      let(:unsupported_reason) { nil }

      it 'does not log a message' do
        expect(Datadog.logger).to_not receive(:info)

        check_if_cpu_time_profiling_is_supported
      end
    end

    context 'when CPU time profiling is not supported' do
      let(:unsupported_reason) { 'Simulated failure' }

      it 'logs info message' do
        expect(Datadog.logger).to receive(:info) do |&message|
          expect(message.call).to include('CPU time profiling skipped')
        end

        check_if_cpu_time_profiling_is_supported
      end
    end
  end

  describe '#setup_at_fork_hooks' do
    subject(:setup_at_fork_hooks) { task.send(:setup_at_fork_hooks) }

    context 'when Process#at_fork is available' do
      before do
        allow(Process).to receive(:respond_to?).with(:at_fork).and_return(true)
        allow(Datadog::Profiling).to receive(:start_if_enabled)

        without_partial_double_verification do
          allow(Process).to receive(:at_fork)
        end
      end

      let(:at_fork_hook) do
        the_hook = nil

        without_partial_double_verification do
          expect(Process).to receive(:at_fork).with(:child) do |&block|
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

    context 'when #at_fork is not available' do
      before do
        allow(Process).to receive(:respond_to?).with(:at_fork).and_return(false)
      end

      it 'does nothing' do
        without_partial_double_verification do
          expect(Process).to_not receive(:at_fork)

          setup_at_fork_hooks
        end
      end
    end
  end

  describe '#cpu_time_profiling_unsupported_reason' do
    subject(:cpu_time_profiling_unsupported_reason) { task.send(:cpu_time_profiling_unsupported_reason) }

    context 'when JRuby is used' do
      before { stub_const('RUBY_ENGINE', 'jruby') }

      it { is_expected.to include 'JRuby' }
    end

    context 'when using MRI Ruby' do
      before { stub_const('RUBY_ENGINE', 'ruby') }

      context 'when running on macOS' do
        before { stub_const('RUBY_PLATFORM', 'x86_64-darwin19') }

        it { is_expected.to include 'macOS' }
      end

      context 'when running on Windows' do
        before { stub_const('RUBY_PLATFORM', 'mswin') }

        it { is_expected.to include 'Windows' }
      end

      context 'when running on a non-Linux platform' do
        before { stub_const('RUBY_PLATFORM', 'my-homegrown-os') }

        it { is_expected.to include 'my-homegrown-os' }
      end

      context 'when running on Linux' do
        before { stub_const('RUBY_PLATFORM', 'x86_64-linux-gnu') }

        it { is_expected.to be nil }
      end
    end
  end
end
