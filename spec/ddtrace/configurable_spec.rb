require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Configurable do
  shared_examples_for 'a configurable constant' do
    describe '#option' do
      let(:name) { :foo }
      let(:options) { {} }
      let(:block) { nil }
      before(:each) { configurable.send(:option, name, options, &block) }

      context 'given a default option' do
        let(:options) { { default: default_value } }
        let(:default_value) { :bar }
        it { expect(configurable.get_option(name)).to eq(default_value) }
      end

      context 'given a custom setter' do
        let(:name) { :shout }
        before(:each) { configurable.set_option(name, 'loud') }

        context 'option' do
          let(:options) { { setter: ->(v) { v.upcase } } }
          it { expect(configurable.get_option(name)).to eq('LOUD') }
        end

        context 'block' do
          let(:block) { proc { |value| "#{value.upcase}!" } }
          it { expect(configurable.get_option(name)).to eq('LOUD!') }
        end
      end
    end

    describe '#get_option' do
      subject(:result) { configurable.get_option(name) }
      let(:name) { :foo }
      let(:options) { {} }

      it { expect(configurable).to respond_to(:get_option) }

      context 'when the option doesn\'t exist' do
        it { expect { result }.to raise_error(Datadog::InvalidOptionError) }
      end
    end

    describe '#set_option' do
      let(:name) { :foo }
      let(:options) { {} }
      let(:value) { :bar }

      before(:each) do
        configurable.send(:option, name, options)
        configurable.set_option(name, value)
      end

      it { expect(configurable).to respond_to(:set_option) }

      context 'when a default has been defined' do
        let(:options) { { default: default_value } }
        let(:default_value) { :bar }
        let(:value) { 'baz!' }
        it { expect(configurable.get_option(name)).to eq(value) }

        context 'and the value set is \'false\'' do
          let(:default_value) { true }
          let(:value) { false }
          it { expect(configurable.get_option(name)).to eq(value) }
        end
      end

      context 'when the option doesn\'t exist' do
        subject(:result) { configurable.set_option(:bad_option, value) }
        it { expect { result }.to raise_error(Datadog::InvalidOptionError) }
      end
    end

    describe '#to_h' do
      subject(:hash) { configurable.to_h }

      before(:each) do
        configurable.send(:option, :x, default: 1)
        configurable.send(:option, :y, default: 2)
        configurable.set_option(:y, 100)
      end

      it { is_expected.to eq(x: 1, y: 100) }
    end

    describe '#sorted_options' do
      subject(:sorted_options) { configurable.sorted_options }

      before(:each) do
        configurable.send(:option, :foo, depends_on: [:bar])
        configurable.send(:option, :bar, depends_on: [:baz])
        configurable.send(:option, :baz)
      end

      it { is_expected.to eq([:baz, :bar, :foo]) }
    end
  end

  describe 'implemented' do
    describe 'class' do
      subject(:configurable) { Class.new { include(Datadog::Configurable) } }
      it_behaves_like 'a configurable constant'
    end

    describe 'module' do
      subject(:configurable) { Module.new { include(Datadog::Configurable) } }
      it_behaves_like 'a configurable constant'
    end
  end
end
