require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/lograge/integration'

RSpec.describe Datadog::Tracing::Contrib::Lograge::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:lograge) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "lograge" gem is loaded' do
      include_context 'loaded gems', :lograge => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "lograge" gem is not loaded' do
      include_context 'loaded gems', :lograge => nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Lograge is defined' do
      before { stub_const('Lograge::LogSubscribers::Base', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Lograge is not defined' do
      before { hide_const('Lograge::LogSubscribers::Base') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "lograge" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', :lograge => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', :lograge => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', :lograge => nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be false }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Lograge::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Lograge::Patcher }
  end
end
