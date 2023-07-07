require 'datadog/ci/contrib/support/spec_helper'

require 'datadog/ci/contrib/minitest/integration'

RSpec.describe Datadog::CI::Contrib::Minitest::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:minitest) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "minitest" gem is loaded' do
      include_context 'loaded gems', 'minitest' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "minitest" gem is not loaded' do
      include_context 'loaded gems', 'minitest' => nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Minitest is defined' do
      it { is_expected.to be true }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "minitest" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', 'minitest' => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', 'minitest' => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', 'minitest' => nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(false) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::CI::Contrib::Minitest::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::CI::Contrib::Minitest::Patcher }
  end
end
