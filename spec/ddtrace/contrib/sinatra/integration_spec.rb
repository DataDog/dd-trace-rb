require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/sinatra/integration'

RSpec.describe Datadog::Contrib::Sinatra::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:sinatra) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "sinatra" gem is loaded' do
      include_context 'loaded gems', sinatra: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "sinatra" gem is not loaded' do
      include_context 'loaded gems', sinatra: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Sinatra is defined' do
      before { stub_const('Sinatra', Class.new) }
      it { is_expected.to be true }
    end

    context 'when Sinatra is not defined' do
      before { hide_const('Sinatra') }
      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "sinatra" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', sinatra: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', sinatra: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', sinatra: nil
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }
    it { is_expected.to be_a_kind_of(Datadog::Contrib::Sinatra::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }
    it { is_expected.to be Datadog::Contrib::Sinatra::Patcher }
  end
end
