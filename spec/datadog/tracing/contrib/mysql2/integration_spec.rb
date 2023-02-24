require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/mysql2/integration'

RSpec.describe Datadog::Tracing::Contrib::Mysql2::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:mysql2) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "mysql2" gem is loaded' do
      include_context 'loaded gems', mysql2: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "mysql2" gem is not loaded' do
      include_context 'loaded gems', mysql2: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Mysql2 is defined' do
      before { stub_const('Mysql2', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Mysql2 is not defined' do
      before { hide_const('Mysql2') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "mysql2" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', mysql2: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', mysql2: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', mysql2: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Mysql2::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Mysql2::Patcher }
  end
end
