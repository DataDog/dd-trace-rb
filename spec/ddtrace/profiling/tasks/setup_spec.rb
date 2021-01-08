require 'spec_helper'
require 'ddtrace/profiling/spec_helper'

require 'ddtrace/profiling'
require 'ddtrace/profiling/tasks/setup'
require 'ddtrace/profiling/ext/forking'

RSpec.describe Datadog::Profiling::Tasks::Setup do
  subject(:task) { described_class.new }

  describe '#run' do
    subject(:run) { task.run }

    it do
      expect(task).to receive(:check_warnings!).ordered
      expect(task).to receive(:activate_main_extensions).ordered
      expect(task).to receive(:autostart_profiler).ordered
      run
    end
  end

  describe '#activate_main_extensions' do
    subject(:activate_main_extensions) { task.activate_main_extensions }

    before do
      expect(task).to receive(:activate_forking_extensions).ordered
      expect(task).to receive(:activate_cpu_extensions).ordered
    end

    context 'and Process' do
      context 'responds to #at_fork' do
        it do
          without_partial_double_verification do
            allow(Process)
              .to receive(:respond_to?)
              .and_call_original

            allow(Process)
              .to receive(:respond_to?)
              .with(:at_fork)
              .and_return(true)

            expect(Process).to receive(:at_fork) do |stage, &block|
              expect(stage).to eq(:child)
              # Might be better to assert it attempts to update native IDs here
              expect(block).to_not be nil
            end

            activate_main_extensions
          end
        end
      end

      context 'does not respond to #at_fork' do
        before do
          allow(Process)
            .to receive(:respond_to?)
            .and_call_original

          allow(Process)
            .to receive(:respond_to?)
            .with(:at_fork, any_args)
            .and_return(false)
        end

        it do
          without_partial_double_verification do
            expect(Process).to_not receive(:at_fork)
            activate_main_extensions
          end
        end
      end
    end
  end

  describe '#activate_forking_extensions' do
    subject(:activate_forking_extensions) { task.activate_forking_extensions }

    context 'when forking extensions are supported' do
      before do
        allow(Datadog::Profiling::Ext::Forking)
          .to receive(:supported?)
          .and_return(true)
      end

      context 'and succeeds' do
        it 'applies forking extensions' do
          expect(Datadog::Profiling::Ext::Forking).to receive(:apply!)
          expect(STDOUT).to_not receive(:puts)
          activate_forking_extensions
        end
      end

      context 'but fails' do
        before do
          expect(Datadog::Profiling::Ext::Forking)
            .to receive(:apply!)
            .and_raise(StandardError)
        end

        it 'displays a warning to STDOUT' do
          expect(STDOUT).to receive(:puts) do |message|
            expect(message).to include('Forking extensions unavailable')
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
          expect(STDOUT).to receive(:puts) do |message|
            expect(message).to include('Forking extensions skipped')
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
          expect(STDOUT).to_not receive(:puts)
          activate_forking_extensions
        end
      end
    end
  end

  describe '#activate_cpu_extensions' do
    subject(:activate_cpu_extensions) { task.activate_cpu_extensions }

    context 'when CPU extensions are supported' do
      before do
        allow(Datadog::Profiling::Ext::CPU)
          .to receive(:supported?)
          .and_return(true)
      end

      context 'and succeeds' do
        it 'applies CPU extensions' do
          expect(Datadog::Profiling::Ext::CPU).to receive(:apply!)
          expect(STDOUT).to_not receive(:puts)
          activate_cpu_extensions
        end
      end

      context 'but fails' do
        before do
          expect(Datadog::Profiling::Ext::CPU)
            .to receive(:apply!)
            .and_raise(StandardError)
        end

        it 'displays a warning to STDOUT' do
          expect(STDOUT).to receive(:puts) do |message|
            expect(message).to include('CPU profiling unavailable')
          end

          activate_cpu_extensions
        end
      end
    end

    context 'when CPU extensions are not supported' do
      before do
        allow(Datadog::Profiling::Ext::CPU)
          .to receive(:supported?)
          .and_return(false)
      end

      context 'and profiling is enabled' do
        before do
          allow(Datadog.configuration.profiling)
            .to receive(:enabled)
            .and_return(true)
        end

        it 'skips CPU extensions with warning' do
          expect(Datadog::Profiling::Ext::CPU).to_not receive(:apply!)
          expect(STDOUT).to receive(:puts) do |message|
            expect(message).to include('CPU profiling skipped')
          end

          activate_cpu_extensions
        end
      end

      context 'and profiling is disabled' do
        before do
          allow(Datadog.configuration.profiling)
            .to receive(:enabled)
            .and_return(false)
        end

        it 'skips CPU extensions without warning' do
          expect(Datadog::Profiling::Ext::CPU).to_not receive(:apply!)
          expect(STDOUT).to_not receive(:puts)
          activate_cpu_extensions
        end
      end
    end
  end

  describe '#autostart_profiler' do
    subject(:autostart_profiler) { task.autostart_profiler }

    context 'when profiling' do
      context 'is supported' do
        let(:profiler) { instance_double(Datadog::Profiler) }

        before do
          skip 'Profiling not supported.' unless defined?(Datadog::Profiler)

          allow(Datadog::Profiling)
            .to receive(:supported?)
            .and_return(true)

          allow(Datadog)
            .to receive(:profiler)
            .and_return(profiler)
        end

        context 'and Process' do
          context 'responds to #at_fork' do
            it do
              without_partial_double_verification do
                allow(Process)
                  .to receive(:respond_to?)
                  .and_call_original

                allow(Process)
                  .to receive(:respond_to?)
                  .with(:at_fork)
                  .and_return(true)

                expect(profiler).to receive(:start)

                expect(Process).to receive(:at_fork) do |stage, &block|
                  expect(stage).to eq(:child)
                  # Might be better to assert it attempts to restart the profiler here
                  expect(block).to_not be nil
                end

                autostart_profiler
              end
            end
          end

          context 'does not respond to #at_fork' do
            before do
              allow(Process)
                .to receive(:respond_to?)
                .and_call_original

              allow(Process)
                .to receive(:respond_to?)
                .with(:at_fork, any_args)
                .and_return(false)
            end

            it do
              without_partial_double_verification do
                expect(Process).to_not receive(:at_fork)
                expect(profiler).to receive(:start)
                autostart_profiler
              end
            end
          end
        end

        context 'but it fails' do
          before do
            expect(Datadog)
              .to receive(:profiler)
              .and_raise(StandardError)
          end

          it 'displays a warning to STDOUT' do
            expect(STDOUT).to receive(:puts) do |message|
              expect(message).to include('Could not autostart profiling')
            end

            autostart_profiler
          end
        end
      end

      context 'isn\'t supported' do
        before do
          allow(Datadog::Profiling)
            .to receive(:supported?)
            .and_return(false)
        end

        context 'and profiling is enabled' do
          before do
            allow(Datadog.configuration.profiling)
              .to receive(:enabled)
              .and_return(true)
          end

          it 'skips profiling autostart with warning' do
            expect(Datadog).to_not receive(:profiler)
            expect(STDOUT).to receive(:puts) do |message|
              expect(message).to include('Profiling did not autostart')
            end

            autostart_profiler
          end
        end

        context 'and profiling is disabled' do
          before do
            allow(Datadog.configuration.profiling)
              .to receive(:enabled)
              .and_return(false)
          end

          it 'skips profiling autostart without warning' do
            expect(Datadog).to_not receive(:profiler)
            expect(STDOUT).to_not receive(:puts)
            autostart_profiler
          end
        end
      end
    end
  end

  describe '#check_warnings!' do
    subject(:check_warnings!) { task.check_warnings! }

    it do
      expect(task).to receive(:warn_if_incompatible_rollbar_gem_detected)

      check_warnings!
    end
  end

  describe '#warn_if_incompatible_rollbar_gem_detected' do
    subject(:warn_if_incompatible_rollbar_gem_detected) { task.warn_if_incompatible_rollbar_gem_detected }

    let(:last_version_of_rollbar_affected) { '3.1.1' }

    before do
      # Simulate the result of the gem apis, so that we can check different combinations of having or not having the
      # rollbar gem and affected versions
      expect(Gem::Specification)
        .to receive(:find_all_by_name)
        .with('rollbar', Gem::Requirement.new("<= #{last_version_of_rollbar_affected}"))
        .and_return(rollbar_versions_found)
    end

    context 'when rollbar gem is not installed' do
      let(:rollbar_versions_found) { [] }

      it 'does not display a warning to STDOUT' do
        expect(STDOUT).to_not receive(:puts)

        warn_if_incompatible_rollbar_gem_detected
      end
    end

    context 'when compatible version of rollbar gem is installed' do
      # same as "no gem installed" because we use a version requirement when
      # calling find_all_by_name, so only incompatible versions get returned
      let(:rollbar_versions_found) { [] }

      it 'does not display a warning to STDOUT' do
        expect(STDOUT).to_not receive(:puts)

        warn_if_incompatible_rollbar_gem_detected
      end
    end

    context 'when incompatible version of rollbar gem is installed' do
      let(:rollbar_versions_found) { [instance_double(Gem::Specification), instance_double(Gem::Specification)] }

      it 'displays a warning to STDOUT' do
        expect(STDOUT).to receive(:puts) do |message|
          expect(message).to include('Incompatible version of the rollbar')
        end

        warn_if_incompatible_rollbar_gem_detected
      end
    end
  end
end
