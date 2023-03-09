require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/redis/integration'

RSpec.describe Datadog::Tracing::Contrib::Redis::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:redis) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when `redis` gem and `redis-client` are loaded' do
      include_context 'loaded gems',
        redis: described_class::MINIMUM_VERSION,
        'redis-client' => described_class::REDISCLIENT_MINIMUM_VERSION

      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when `redis` gem is loaded' do
      include_context 'loaded gems',
        redis: described_class::MINIMUM_VERSION,
        'redis-client' => nil

      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when `redis-client` gem is loaded' do
      include_context 'loaded gems',
        redis: nil,
        'redis-client' => described_class::REDISCLIENT_MINIMUM_VERSION

      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when `redis` gem and `redis-client` are not loaded' do
      include_context 'loaded gems', redis: nil, 'redis-client' => nil

      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when `Redis` and `RedisClient` are defined' do
      before do
        stub_const('Redis', Class.new)
        stub_const('RedisClient', Class.new)
      end

      it { is_expected.to be true }
    end

    context 'when `Redis` is defined' do
      before do
        stub_const('Redis', Class.new)
        hide_const('RedisClient')
      end

      it { is_expected.to be true }
    end

    context 'when `RedisClient` is defined' do
      before do
        hide_const('Redis')
        stub_const('RedisClient', Class.new)
      end

      it { is_expected.to be true }
    end

    context 'when `Redis` and `RedisClient` are not defined' do
      before do
        hide_const('Redis')
        hide_const('RedisClient')
      end

      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when `redis` is compatible' do
      before do
        allow(described_class).to receive(:redis_compatible?).and_return(true)
        allow(described_class).to receive(:redis_client_compatible?).and_return(false)
      end
      it { is_expected.to be true }
    end

    context 'when `redis-client` is compatible' do
      before do
        allow(described_class).to receive(:redis_compatible?).and_return(false)
        allow(described_class).to receive(:redis_client_compatible?).and_return(true)
      end
      it { is_expected.to be true }
    end

    context 'when `redis` and `redis-client` are both incompatible' do
      before do
        allow(described_class).to receive(:redis_compatible?).and_return(false)
        allow(described_class).to receive(:redis_client_compatible?).and_return(false)
      end
      it { is_expected.to be false }
    end
  end

  describe '.redis_compatible?' do
    subject(:compatible?) { described_class.redis_compatible? }

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

  describe '.redis_client_compatible?' do
    subject(:compatible?) { described_class.redis_client_compatible? }

    context 'when "redis-client" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', 'redis-client' => decrement_gem_version(described_class::REDISCLIENT_MINIMUM_VERSION)

        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', 'redis-client' => described_class::REDISCLIENT_MINIMUM_VERSION

        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', 'redis-client' => nil

      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Redis::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::Redis::Patcher }
  end

  describe '#resolver' do
    subject(:resolver) { integration.resolver }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Redis::Configuration::Resolver) }
  end
end
