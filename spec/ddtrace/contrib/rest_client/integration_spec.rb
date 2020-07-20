require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/rest_client/integration'

RSpec.describe Datadog::Contrib::RestClient::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:rest_client) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "rest-client" gem is loaded' do
      include_context 'loaded gems', :'rest-client' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "rest-client" gem is not loaded' do
      include_context 'loaded gems', :'rest-client' => nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when RestClient::Request is defined' do
      before { stub_const('RestClient::Request', Class.new) }
      it { is_expected.to be true }
    end

    context 'when RestClient::Request is not defined' do
      before { hide_const('RestClient::Request') }
      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "rest-client" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', :'rest-client' => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', :'rest-client' => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', :'rest-client' => nil
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }
    it { is_expected.to be_a_kind_of(Datadog::Contrib::RestClient::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }
    it { is_expected.to be Datadog::Contrib::RestClient::Patcher }
  end
end
