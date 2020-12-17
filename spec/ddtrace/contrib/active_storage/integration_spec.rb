require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/active_storage/integration'

RSpec.describe Datadog::Contrib::ActiveStorage::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:active_storage) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "activestorage" gem is loaded' do
      include_context 'loaded gems', activestorage: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "activestorage" gem is not loaded' do
      include_context 'loaded gems', activestorage: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when ActiveStorage is defined' do
      before { stub_const('ActiveStorage', Class.new) }
      it { is_expected.to be true }
    end

    context 'when ActiveStorage is not defined' do
      before { hide_const('ActiveStorage') }
      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "activestorage" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', activestorage: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', activestorage: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', activestorage: nil
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }
    it { is_expected.to be_a_kind_of(Datadog::Contrib::ActiveStorage::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }
    it { is_expected.to be Datadog::Contrib::ActiveStorage::Patcher }
  end
end
