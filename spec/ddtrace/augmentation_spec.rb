require 'spec_helper'

require 'ddtrace/augmentation'

RSpec.describe Datadog::Augmentation do
  context 'when extended' do
    let(:test_module) { Module.new { extend Datadog::Augmentation } }

    describe '#shim' do
      subject(:shim) { test_module.shim(object, &block) }
      let(:object) { double('object') }
      let(:block) { proc {} }

      it { expect(Datadog::Shim.shim?(shim)).to be true }
      it do
        expect { |b| test_module.shim(object, &b) }.to yield_with_args(
          a_kind_of(Datadog::Shim)
        )
      end
    end
  end
end
