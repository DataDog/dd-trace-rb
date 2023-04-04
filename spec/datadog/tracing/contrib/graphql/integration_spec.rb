require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/graphql/integration'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:graphql) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "graphql" gem is loaded' do
      include_context 'loaded gems', graphql: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "graphql" gem is not loaded' do
      include_context 'loaded gems', graphql: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when neither GraphQL or GraphQL::Tracing::DataDogTracing are defined' do
      before do
        hide_const('GraphQL')
        hide_const('GraphQL::Tracing::DataDogTracing')
      end

      it { is_expected.to be false }
    end

    context 'when only GraphQL is defined' do
      before do
        stub_const('GraphQL', Class.new)
        hide_const('GraphQL::Tracing::DataDogTracing')
      end

      it { is_expected.to be false }
    end

    context 'when GraphQL::Tracing::DataDogTracing is defined' do
      before { stub_const('GraphQL::Tracing::DataDogTracing', Class.new) }

      it { is_expected.to be true }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "graphql" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', graphql: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', graphql: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', graphql: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::GraphQL::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::GraphQL::Patcher }
  end
end
