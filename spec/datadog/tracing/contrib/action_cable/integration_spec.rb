require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/auto_instrument_examples'

require 'datadog/tracing/contrib/action_cable/integration'

RSpec.describe Datadog::Tracing::Contrib::ActionCable::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:action_cable) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "actioncable" gem is loaded' do
      include_context 'loaded gems', actioncable: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "actioncable" gem is not loaded' do
      include_context 'loaded gems', actioncable: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when ActionCable is defined' do
      before { stub_const('ActionCable', Class.new) }

      it { is_expected.to be true }
    end

    context 'when ActionCable is not defined' do
      before { hide_const('ActionCable') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "actioncable" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', actioncable: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', actioncable: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', actioncable: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    it_behaves_like 'rails sub-gem auto_instrument?'
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ActionCable::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::ActionCable::Patcher }
  end
end
