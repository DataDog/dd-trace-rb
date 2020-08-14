require 'spec_helper'
require 'ddtrace/profiling'
require 'ddtrace/profiling/tasks/setup'
require 'ddtrace/profiling/ext/forking'

RSpec.describe Datadog::Profiling::Tasks::Setup do
  subject(:task) { described_class.new }

  describe '#run' do
    subject(:run) { task.run }

    it do
      expect(task).to receive(:activate_main_extensions)
      expect(task).to receive(:activate_thread_extensions)
      run
    end
  end

  describe '#activate_main_extensions' do
    subject(:activate_main_extensions) { task.activate_main_extensions }

    context 'when forking extensions can be applied' do
      before do
        expect(Datadog::Profiling::Ext::Forking)
          .to receive(:apply!)
      end

      it do
        expect(STDOUT).to_not receive(:puts)
        activate_main_extensions
      end
    end

    context 'when forking extensions cannot be applied' do
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

  describe '#activate_thread_extensions' do
    subject(:activate_thread_extensions) { task.activate_thread_extensions }

    around do |example|
      unmodified_class = ::Thread.dup

      example.run

      Object.send(:remove_const, :Thread)
      Object.const_set('Thread', unmodified_class)
    end

    if Datadog::Profiling.native_cpu_time_supported?
      context 'when native CPU time is supported' do
        before { expect(STDOUT).to_not receive(:puts) }

        it 'adds Thread extensions' do
          activate_thread_extensions
          expect(Thread.ancestors).to include(Datadog::Profiling::Ext::CThread)
        end
      end
    else
      context 'when native CPU time is not supported' do
        it 'displays a warning to STDOUT' do
          expect(STDOUT).to receive(:puts) do |message|
            expect(message).to include('CPU profiling unavailable')
          end

          activate_thread_extensions
        end
      end
    end
  end
end
