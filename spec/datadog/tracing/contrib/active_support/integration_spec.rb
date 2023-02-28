require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/auto_instrument_examples'

require 'datadog/tracing/contrib/active_support/integration'

RSpec.describe Datadog::Tracing::Contrib::ActiveSupport::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:active_support) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "activesupport" gem is loaded' do
      include_context 'loaded gems', activesupport: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "activesupport" gem is not loaded' do
      include_context 'loaded gems', activesupport: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when ActiveSupport is defined' do
      before { stub_const('ActiveSupport', Class.new) }

      it { is_expected.to be true }
    end

    context 'when ActiveSupport is not defined' do
      before { hide_const('ActiveSupport') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "activesupport" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', activesupport: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', activesupport: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', activesupport: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    it_behaves_like 'rails sub-gem auto_instrument?'
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ActiveSupport::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::ActiveSupport::Patcher }
  end
end
