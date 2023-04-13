require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/stripe/integration'

RSpec.describe Datadog::Tracing::Contrib::Stripe::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:stripe) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "stripe" gem is loaded' do
      include_context 'loaded gems', stripe: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "stripe" gem is not loaded' do
      include_context 'loaded gems', stripe: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Stripe is defined' do
      before { stub_const('Stripe', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Stripe is not defined' do
      before { hide_const('Stripe') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "stripe" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', stripe: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', stripe: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', stripe: nil
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Stripe::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Stripe::Patcher }
  end
end
