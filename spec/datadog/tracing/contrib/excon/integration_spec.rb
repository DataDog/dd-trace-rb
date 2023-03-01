require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/excon/integration'

RSpec.describe Datadog::Tracing::Contrib::Excon::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:excon) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "excon" gem is loaded' do
      include_context 'loaded gems', excon: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "excon" gem is not loaded' do
      include_context 'loaded gems', excon: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Excon is defined' do
      before { stub_const('Excon', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Excon is not defined' do
      before { hide_const('Excon') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "excon" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', excon: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', excon: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', excon: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Excon::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Excon::Patcher }
  end
end
