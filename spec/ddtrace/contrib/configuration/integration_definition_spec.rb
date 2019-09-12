require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::IntegrationDefinition do
  subject(:definition) { described_class.new(name, meta, &block) }

  let(:name) { :foobar }
  let(:meta) { {} }
  let(:block) { nil }

  describe '#default' do
    subject(:default) { definition.default }

    context 'when not initialized with a block' do
      it { is_expected.to be nil }
    end

    context 'when initialized with a block' do
      let(:block) { proc {} }
      it { is_expected.to be block }
    end
  end

  describe '#name' do
    subject(:result) { definition.name }

    context 'when given a String' do
      let(:name) { 'foobar' }
      it { is_expected.to be name.to_sym }
    end

    context 'when given a Symbol' do
      let(:name) { :foobar }
      it { is_expected.to be name }
    end
  end

  describe '#defer?' do
    subject(:defer) { definition.defer? }

    context 'when initialized with nothing' do
      it { is_expected.to be false }
    end

    context 'when initialized with true' do
      let(:meta) { { defer: true } }
      it { is_expected.to be true }
    end

    context 'when initialized with false' do
      let(:meta) { { defer: false } }
      it { is_expected.to be false }
    end

    context 'when initialized with nil' do
      let(:meta) { { defer: nil } }
      it { is_expected.to be false }
    end
  end

  describe '#enabled?' do
    subject(:enabled) { definition.enabled? }

    context 'when initialized with nothing' do
      it { is_expected.to be true }
    end

    context 'when initialized with true' do
      let(:meta) { { enabled: true } }
      it { is_expected.to be true }
    end

    context 'when initialized with false' do
      let(:meta) { { enabled: false } }
      it { is_expected.to be false }
    end

    context 'when initialized with nil' do
      let(:meta) { { enabled: nil } }
      it { is_expected.to be false }
    end
  end
end
