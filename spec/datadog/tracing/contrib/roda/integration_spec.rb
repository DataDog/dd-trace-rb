# typed: ignore

require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/roda/integration'

RSpec.describe Datadog::Tracing::Contrib::Roda::Integration do
  let(:integration) { described_class.new(:roda) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "roda" gem is loaded' do
      include_context 'loaded gems', roda: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "roda" gem is not loaded' do
      include_context 'loaded gems', roda: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Roda is defined' do
      before { stub_const('Roda', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Roda is not defined' do
      before { hide_const('Roda') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "roda" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', roda: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', roda: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end

      context 'that exceeds the maximum version' do
        unsupported_major_release = described_class::MAXIMUM_VERSION.segments[0] + 1
        unsupported_gem = Gem::Version.new(unsupported_major_release.to_s + '.0.0')
        include_context 'loaded gems', roda: unsupported_gem
        it { is_expected.to be false }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', roda: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Roda::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Roda::Patcher }
  end
end
