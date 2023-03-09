require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/aws/integration'

RSpec.describe Datadog::Tracing::Contrib::Aws::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:aws) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "aws-sdk" gem is loaded' do
      include_context 'loaded gems', :'aws-sdk' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "aws-sdk" gem is not loaded but aws-sdk-core is' do
      include_context 'loaded gems', :'aws-sdk' => nil, :'aws-sdk-core' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when neither "aws-sdk" or "aws-sdk-core" gems are loaded' do
      include_context 'loaded gems', :'aws-sdk' => nil, :'aws-sdk-core' => nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Seahorse::Client::Base is defined' do
      before { stub_const('Seahorse::Client::Base', Class.new) }

      it { is_expected.to be true }
    end

    context 'when Seahorse::Client::Base is not defined' do
      before { hide_const('Seahorse::Client::Base') }

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "aws-sdk" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', :'aws-sdk' => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', :'aws-sdk' => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', :'aws-sdk' => nil, :'aws-sdk-core' => nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Aws::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Aws::Patcher }
  end
end
