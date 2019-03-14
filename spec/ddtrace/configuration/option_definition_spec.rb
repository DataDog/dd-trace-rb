require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Configuration::OptionDefinition do
  subject(:definition) { described_class.new(name, meta, &block) }

  let(:name) { :enabled }
  let(:meta) { {} }
  let(:block) { nil }

  describe '#default' do
    subject(:default) { definition.default }

    context 'when not initialized with a value' do
      it { is_expected.to be nil }
    end

    context 'when initialized with a value' do
      let(:meta) { { default: default_value } }
      let(:default_value) { double('default') }
      it { is_expected.to be default_value }
    end
  end

  describe '#depends_on' do
    subject(:default) { definition.depends_on }

    context 'when not initialized with a value' do
      it { is_expected.to eq([]) }
    end

    context 'when initialized with a value' do
      let(:meta) { { depends_on: depends_on_value } }
      let(:depends_on_value) { double('depends_on') }
      it { is_expected.to be depends_on_value }
    end
  end

  describe '#lazy' do
    subject(:lazy) { definition.lazy }

    context 'when not initialized with a value' do
      it { is_expected.to be false }
    end

    context 'when initialized with a value' do
      let(:meta) { { lazy: lazy_value } }
      let(:lazy_value) { double('lazy') }
      it { is_expected.to be lazy_value }
    end
  end

  describe '#name' do
    subject(:result) { definition.name }

    context 'when given a String' do
      let(:name) { 'enabled' }
      it { is_expected.to be name.to_sym }
    end

    context 'when given a Symbol' do
      let(:name) { :enabled }
      it { is_expected.to be name }
    end
  end

  describe '#setter' do
    subject(:setter) { definition.setter }

    context 'when given a value' do
      let(:meta) { { setter: setter_value } }
      let(:setter_value) { double('setter') }
      it { is_expected.to be setter_value }
    end

    context 'when initialized with a block' do
      let(:block) { proc {} }
      it { is_expected.to be block }
    end

    context 'when not initialized' do
      it { is_expected.to be described_class::IDENTITY }
    end
  end

  describe '#default_value' do
    subject(:result) { definition.default_value }
    let(:meta) { { default: default } }
    let(:default) { double('default') }

    context 'when lazy is true' do
      let(:meta) { super().merge(lazy: true) }
      let(:default_value) { double('default_value') }
      before(:each) { expect(default).to receive(:call).and_return(default_value) }
      it { is_expected.to be default_value }
    end

    context 'when lazy is false' do
      let(:meta) { super().merge(lazy: false) }
      it { is_expected.to be default }
    end
  end
end
