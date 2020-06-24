require 'spec_helper'
require 'ddtrace/profiling'
require 'ddtrace/profiling/tasks/setup'

RSpec.describe Datadog::Profiling::Tasks::Setup do
  subject(:task) { described_class.new }

  describe '#run' do
    subject(:run) { task.run }

    if Datadog::Profiling.native_cpu_time_supported?
      context 'when native CPU time is supported' do
        around do |example|
          unmodified_class = ::Thread.dup

          example.run

          Object.send(:remove_const, :Thread)
          Object.const_set('Thread', unmodified_class)
        end

        before { expect(STDOUT).to_not receive(:puts) }

        it 'adds Thread extensions' do
          run
          expect(Thread.ancestors).to include(Datadog::Profiling::Ext::CThread)
        end
      end
    else
      context 'when native CPU time is not supported' do
        it 'displays a warning to STDOUT' do
          expect(STDOUT).to receive(:puts) do |message|
            expect(message).to include('CPU profiling unavailable')
          end

          task.run
        end
      end
    end
  end
end
