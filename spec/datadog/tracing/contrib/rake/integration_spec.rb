require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/rake/integration'

RSpec.describe Datadog::Tracing::Contrib::Rake::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:rake) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "rake" gem is loaded' do
      include_context 'loaded gems', rake: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "rake" gem is not loaded' do
      include_context 'loaded gems', rake: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Rake::Task is defined' do
      before { stub_const('Rake::Task', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Rake is not defined' do
      before { hide_const('Rake') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "rake" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', rake: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', rake: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', rake: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Rake::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Rake::Patcher }
  end
end
