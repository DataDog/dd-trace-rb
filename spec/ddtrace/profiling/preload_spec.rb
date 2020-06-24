require 'spec_helper'
require 'ddtrace/profiling'

RSpec.describe 'Profiling preloading' do
  subject(:preload) { load 'ddtrace/profiling/preload.rb' }

  shared_examples_for 'skipped preloading' do
    it 'displays a warning' do
      expect(STDOUT).to receive(:puts) do |message|
        expect(message).to include('Profiling not supported')
      end

      preload
    end
  end

  context 'when profiling is not supported' do
    before { allow(Datadog::Profiling).to receive(:supported?).and_return(false) }
    it_behaves_like 'skipped preloading'
  end

  context 'when native CPU time is not supported' do
    before { allow(Datadog::Profiling).to receive(:native_cpu_time_supported?).and_return(false) }
    it_behaves_like 'skipped preloading'
  end

  context 'when profiling and native CPU time is supported' do
    let(:setup_task) { instance_double(Datadog::Profiling::Tasks::Setup) }

    before do
      allow(Datadog::Profiling).to receive(:supported?).and_return(true)
      allow(Datadog::Profiling).to receive(:native_cpu_time_supported?).and_return(true)
      allow(Datadog::Profiling::Tasks::Setup).to receive(:new).and_return(setup_task)
    end

    it 'preloads without warning' do
      expect(setup_task).to receive(:run)
      expect(STDOUT).to_not receive(:puts)
      preload
    end
  end
end
