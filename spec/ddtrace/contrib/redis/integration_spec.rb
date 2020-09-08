require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/redis/integration'

RSpec.describe Datadog::Contrib::Redis::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:redis) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "redis" gem is loaded' do
      include_context 'loaded gems', redis: described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "redis" gem is not loaded' do
      include_context 'loaded gems', redis: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Redis is defined' do
      before { stub_const('Redis', Class.new) }
      it { is_expected.to be true }
    end

    context 'when Redis is not defined' do
      before { hide_const('Redis') }
      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "redis" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', redis: decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', redis: described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', redis: nil
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }
    it { is_expected.to be_a_kind_of(Datadog::Contrib::Redis::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }
    it { is_expected.to be Datadog::Contrib::Redis::Patcher }
  end

  describe '#resolver' do
    subject(:resolver) { integration.resolver }
    it { is_expected.to be_a_kind_of(Datadog::Contrib::Redis::Configuration::Resolver) }
  end
end
