require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/http/integration'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:http) }

  describe '.version' do
    subject(:version) { described_class.version }

    it { is_expected.to eq(Gem::Version.new(RUBY_VERSION)) }
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Net::HTTP is defined' do
      before { stub_const('Net::HTTP', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Net::HTTP is not defined' do
      before { hide_const('Net::HTTP') }

      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::HTTP::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::HTTP::Patcher }
  end
end
