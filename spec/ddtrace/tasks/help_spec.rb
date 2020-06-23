require 'spec_helper'
require 'ddtrace/tasks/help'

RSpec.describe Datadog::Tasks::Help do
  subject(:task) { described_class.new }

  describe '#run' do
    it 'prints a help message to STDOUT' do
      expect(STDOUT).to receive(:puts) do |message|
        expect(message).to include('Usage: ddtrace')
      end

      task.run
    end
  end
end
