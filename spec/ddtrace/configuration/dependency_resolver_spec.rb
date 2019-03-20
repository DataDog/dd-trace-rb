require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Configuration::DependencyResolver do
  subject(:resolver) { described_class.new(graph) }

  describe '#call' do
    subject(:order) { resolver.call }

    context 'given a set of dependencies' do
      let(:graph) { { 1 => [2], 2 => [3, 4], 3 => [], 4 => [3], 5 => [1] } }
      it { expect(order).to eq([3, 4, 2, 1, 5]) }
    end

    context 'given cyclic dependencies' do
      let(:graph) { { 1 => [2], 2 => [1] } }
      it { expect { order }.to raise_error(TSort::Cyclic) }
    end
  end
end
