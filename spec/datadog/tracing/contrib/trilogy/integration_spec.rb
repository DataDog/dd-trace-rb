require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/trilogy/integration'

RSpec.describe Datadog::Tracing::Contrib::Trilogy::Integration do
  let(:integration) { described_class.new(:trilogy) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "trilogy" gem is loaded' do
      include_context 'loaded gems', trilogy: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "trilogy" gem is not loaded' do
      include_context 'loaded gems', trilogy: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Trilogy is defined' do
      before { stub_const('Trilogy', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Trilogy is not defined' do
      before { hide_const('Trilogy') }

      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Trilogy::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Trilogy::Patcher }
  end
end
