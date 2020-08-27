require 'spec_helper'
require 'ddtrace/profiling'

RSpec.describe 'Profiling preloading' do
  subject(:preload) { load 'ddtrace/profiling/preload.rb' }
  let(:setup_task) { instance_double(Datadog::Profiling::Tasks::Setup) }

  before do
    allow(Datadog::Profiling::Tasks::Setup).to receive(:new).and_return(setup_task)
  end

  it 'runs the Profiling::Tasks::Setup task' do
    expect(setup_task).to receive(:run)
    preload
  end
end
