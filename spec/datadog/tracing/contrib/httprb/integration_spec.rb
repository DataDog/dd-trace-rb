require 'spec_helper'

require 'datadog/tracing/contrib/httprb/integration'

RSpec.describe Datadog::Tracing::Contrib::Httprb::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:http) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "http.rb" gem is loaded' do
      include_context 'loaded gems', http: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "http.rb" gem is not loaded' do
      include_context 'loaded gems', http: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when HTTP is defined' do
      before { stub_const('HTTP::Client', Class.new) }

      it { is_expected.to be true }
    end

    context 'when HTTP is not defined' do
      before { hide_const('HTTP') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "http.rb" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', http: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', http: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', http: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Httprb::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Httprb::Patcher }
  end
end
