require 'datadog/ci/contrib/support/spec_helper'

require 'datadog/ci/contrib/rspec/integration'

RSpec.describe Datadog::CI::Contrib::RSpec::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:rspec) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "rspec-core" gem is loaded' do
      include_context 'loaded gems', 'rspec-core' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "rspec-core" gem is not loaded' do
      include_context 'loaded gems', 'rspec-core' => nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when RSpec is defined' do
      it { is_expected.to be true }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "rspec-core" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', 'rspec-core' => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', 'rspec-core' => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', 'rspec-core' => nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(false) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::CI::Contrib::RSpec::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::CI::Contrib::RSpec::Patcher }
  end
end
