require 'spec_helper'
require 'ddtrace/profiling'
require 'ddtrace/profiling/tasks/setup'
require 'ddtrace/profiling/ext/forking'

RSpec.describe Datadog::Profiling::Tasks::Setup do
  subject(:task) { described_class.new }

  describe '#run' do
    subject(:run) { task.run }

    it do
      expect(task).to receive(:activate_main_extensions).ordered
      expect(task).to receive(:activate_cpu_extensions).ordered
      run
    end
  end

  describe '#activate_main_extensions' do
    subject(:activate_main_extensions) { task.activate_main_extensions }

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
          activate_main_extensions
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

          activate_main_extensions
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

          activate_main_extensions
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
          activate_main_extensions
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
end
