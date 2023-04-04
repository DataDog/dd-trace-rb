require 'spec_helper'
require 'datadog/profiling/tasks/help'

RSpec.describe Datadog::Profiling::Tasks::Help do
  subject(:task) { described_class.new }

  describe '#run' do
    it 'prints a help message to stdout' do
      expect($stdout).to receive(:puts) do |message|
        expect(message).to include('Usage: ddtrace')
      end

      task.run
    end
  end
end
