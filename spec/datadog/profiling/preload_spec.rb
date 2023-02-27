require 'spec_helper'
require 'datadog/profiling'

RSpec.describe 'Profiling preloading' do
  subject(:preload) { load 'datadog/profiling/preload.rb' }

  it 'starts the profiler' do
    expect(Datadog::Profiling).to receive(:start_if_enabled)

    preload
  end
end
