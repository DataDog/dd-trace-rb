require 'spec_helper'
require 'ddtrace/profiling'

RSpec.describe 'Profiling preloading' do
  subject(:preload) { load 'ddtrace/profiling/preload.rb' }

  it 'starts the profiler' do
    profiler = instance_double(Datadog::Profiler)

    expect(Datadog).to receive(:profiler).and_return(profiler).at_least(:once)
    expect(profiler).to receive(:start)

    preload
  end

  context 'when the profiler is not available' do
    it 'does not raise any error' do
      expect(Datadog).to receive(:profiler).and_return(nil)

      preload
    end
  end
end
