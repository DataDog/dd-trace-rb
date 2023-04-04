require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/auto_instrument_examples'

require 'datadog/tracing/contrib/action_view/integration'

RSpec.describe Datadog::Tracing::Contrib::ActionView::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:action_view) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "actionview" gem is loaded' do
      include_context 'loaded gems', actionview: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "actionview" gem is not loaded' do
      context 'and "actionpack" gem is loaded' do
        context 'of version < 4.1' do
          include_context 'loaded gems', actionview: nil, actionpack: Gem::Version.new('4.0')
          it { is_expected.to be_a_kind_of(Gem::Version) }
        end

        context 'of version >= 4.1' do
          include_context 'loaded gems', actionview: nil, actionpack: Gem::Version.new('4.1')
          # Because in Rails 4.1+, if ActionView isn't present, then there is no version.
          it { is_expected.to be nil }
        end
      end
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when ActionView is defined' do
      before { stub_const('ActionView', Class.new) }

      it { is_expected.to be true }
    end

    context 'when ActionView is not defined' do
      before { hide_const('ActionView') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "actionview" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', actionview: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', actionview: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', actionpack: nil, actionview: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    it_behaves_like 'rails sub-gem auto_instrument?'
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ActionView::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::ActionView::Patcher }
  end
end
