require 'spec_helper'

require 'ddtrace/augmentation/shim'

RSpec.describe Datadog::Shim do
  let(:object) { double('object', test: 'test') }
  let(:wrapper) { spy('wrapper') }

  describe '::shim?' do
    subject(:shim?) { described_class.shim?(object) }

    context 'given a plain object' do
      it { is_expected.to be false }
    end

    context 'given a Datadog::Shim' do
      let(:object) { described_class.new(super()) }
      it { is_expected.to be true }
    end
  end

  describe '#new' do
    subject(:shim) { described_class.new(object, &block) }
    let(:block) { proc {} }

    it { expect(described_class.shim?(shim)).to be true }
    it do
      expect { |b| described_class.new(object, &b) }.to yield_with_args(
        a_kind_of(Datadog::Shim)
      )
    end
  end

  describe '#shim' do
    subject(:shim) { described_class.new(object).shim }
    it { expect(described_class.shim?(shim)).to be true }
  end

  describe '#shim_target' do
    subject(:shim_target) { described_class.new(object).shim_target }
    it { expect(described_class.shim?(shim_target)).to be false }
    it { is_expected.to be object }
  end

  describe '#override_method!' do
    let(:block) do
      w = wrapper

      proc do |*args, &block|
        w.call(*args, &block)
        shim_target.test
      end
    end

    context 'when done inside #new block' do
      subject(:shim) do
        described_class.new(object) do |shim|
          shim.override_method!(:test, &block)
        end
      end

      it { expect(shim.wrapped_methods).to include(:test) }

      context 'which forwards through the wrapper' do
        let(:original_args) { [:bar, :baz] }
        let(:original_block) { proc {} }

        it 'invokes the original method correctly' do
          expect(shim.test(*original_args, &original_block)).to eq('test')
          expect(wrapper).to have_received(:call)
            .with(*original_args, &original_block)
        end
      end
    end

    context 'when invoked after the object is initialized' do
      subject(:override_method!) { shim.override_method!(:test, &block) }
      let(:shim) { described_class.new(object) }

      it { expect { override_method! }.to change { shim.wrapped_methods.include?(:test) }.from(false).to(true) }

      context 'which forwards through the wrapper' do
        let(:original_args) { [:bar, :baz] }
        let(:original_block) { proc {} }

        before(:each) { override_method! }

        it 'invokes the original method correctly' do
          expect(shim.test(*original_args, &original_block)).to eq('test')
          expect(wrapper).to have_received(:call)
            .with(*original_args, &original_block)
        end
      end
    end
  end

  describe '#wrap_method!' do
    let(:block) do
      proc do |original, *args, &block|
        wrapper.call(*args, &block)
        original.call
      end
    end

    context 'when done inside #new block' do
      subject(:shim) do
        described_class.new(object) do |shim|
          shim.wrap_method!(:test, &block)
        end
      end

      it { expect(shim.wrapped_methods).to include(:test) }

      context 'which forwards through the wrapper' do
        let(:original_args) { [:bar, :baz] }
        let(:original_block) { proc {} }

        it 'invokes the original method correctly' do
          expect(shim.test(*original_args, &original_block)).to eq('test')
          expect(wrapper).to have_received(:call)
            .with(*original_args, &original_block)
        end
      end
    end

    context 'when invoked after the object is initialized' do
      subject(:wrap_method!) { shim.wrap_method!(:test, &block) }
      let(:shim) { described_class.new(object) }

      it { expect { wrap_method! }.to change { shim.wrapped_methods.include?(:test) }.from(false).to(true) }

      context 'which forwards through the wrapper' do
        let(:original_args) { [:bar, :baz] }
        let(:original_block) { proc {} }

        before(:each) { wrap_method! }

        it 'invokes the original method correctly' do
          expect(shim.test(*original_args, &original_block)).to eq('test')
          expect(wrapper).to have_received(:call)
            .with(*original_args, &original_block)
        end
      end
    end
  end

  describe '#respond_to?' do
    let(:shim) { described_class.new(object) }
    it { expect(described_class::METHODS.all? { |m| shim.respond_to?(m) }).to be true }
  end

  describe '#shim?' do
    subject(:shim?) { described_class.new(object).shim? }
    it { is_expected.to be true }
  end
end
