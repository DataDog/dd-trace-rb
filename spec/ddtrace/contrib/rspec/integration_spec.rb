require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/rspec/integration'

RSpec.describe Datadog::Contrib::RSpec::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:rspec) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "rspec" gem is loaded' do
      include_context 'loaded gems', 'rspec' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "rspec" gem is not loaded' do
      include_context 'loaded gems', 'rspec' => nil
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

    context 'when "rspec" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', 'rspec' => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', 'rspec' => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', 'rspec' => nil
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }
    it { is_expected.to be_a_kind_of(Datadog::Contrib::RSpec::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }
    it { is_expected.to be Datadog::Contrib::RSpec::Patcher }
  end
end
