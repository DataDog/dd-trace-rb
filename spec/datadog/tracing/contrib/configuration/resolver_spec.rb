require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/configuration/resolver'

RSpec.describe Datadog::Tracing::Contrib::Configuration::Resolver do
  subject(:resolver) { described_class.new }

  let(:config) { double('config') }

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(value) }

    let(:value) { 'value' }

    context 'with a matcher' do
      before { resolver.add(added_matcher, config) }

      context 'that matches' do
        let(:added_matcher) { value }

        it { is_expected.to be config }
      end

      context 'that does not match' do
        let(:added_matcher) { :different_value }

        it { is_expected.to be nil }
      end
    end

    context 'without a matcher' do
      it { is_expected.to be nil }
    end

    context 'with two matching matchers' do
      before do
        resolver.add(first_matcher, :first)
        resolver.add(second_matcher, :second)
      end

      let(:first_matcher) { 'value' }
      let(:second_matcher) { 'value' }

      it 'returns the latest added one' do
        is_expected.to eq(:second)
      end
    end
  end

  describe '#add' do
    subject(:add) { resolver.add(matcher, config) }

    let(:matcher) { double('matcher') }

    it { is_expected.to be config }

    it 'stores in the configuration field' do
      add
      expect(resolver.configurations).to eq(matcher => config)
    end
  end

  describe '#get' do
    subject(:get) { resolver.get(matcher) }

    let(:matcher) { double('matcher') }

    before { resolver.add(matcher, config) }

    it { is_expected.to be config }

    context 'with a custom #parse_matcher' do
      let(:parsed_matcher) { double('parsed_matcher') }
      let(:resolver) do
        super().tap do |r|
          expect(r).to receive(:parse_matcher).with(matcher).and_return(parsed_matcher).twice
        end
      end

      it { is_expected.to be config }
    end
  end
end

RSpec.describe Datadog::Tracing::Contrib::Configuration::CachingResolver do
  subject(:resolver) { resolver_class.new(cache_limit: cache_limit) }

  let(:cache_limit) { 2 }
  let(:value) { double('value') }

  let(:resolver_class) do
    Class.new(Datadog::Tracing::Contrib::Configuration::Resolver) do
      prepend Datadog::Tracing::Contrib::Configuration::CachingResolver

      def resolve(key)
        @invoked ||= 0
        @invoked += 1
        super
      end

      def invocations
        @invoked ||= 0
      end
    end
  end

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(key) }

    let(:key) { 'key' }

    before { resolver.add(key, value) }

    it 'returns the correct value' do
      expect(resolve).to eq(value)
    end

    it 'calls the original resolver once' do
      resolver.resolve(key)
      resolver.resolve(key)

      expect(resolver.invocations).to eq(1)
    end

    context 'when a matcher key is added' do
      let(:new_key) { 'new_key' }

      it 'busts the cache' do
        expect(resolver.resolve(key)).to eq(value)

        resolver.add(new_key, value)

        expect(resolver.resolve(key)).to eq(value)

        expect(resolver.invocations).to eq(2)
      end
    end

    context 'when the cache is reset' do
      let(:new_key) { 'new_key' }

      it 'busts the cache' do
        expect(resolver.resolve(key)).to eq(value)

        resolver.reset_cache

        expect(resolver.resolve(key)).to eq(value)

        expect(resolver.invocations).to eq(2)
      end
    end

    context 'when the cache size limit is reached' do
      before do
        resolver.resolve('first_key')
        resolver.resolve('second_key')
      end

      it 'removes the oldest entry from the cache' do
        expect { resolver.resolve('third_key') }.to(change { resolver.invocations }.by(1)) # Removes `first_key` from cache
        expect { resolver.resolve('second_key') }.to_not(change { resolver.invocations }) # `second_key` is still cached

        expect { resolver.resolve('first_key') }.to(change { resolver.invocations }.by(1)) # Removes `second_key` from cache
        expect { resolver.resolve('third_key') }.to_not(change { resolver.invocations }) # `third_key` is still cached

        expect { resolver.resolve('second_key') }.to(change { resolver.invocations }.by(1)) # Removes `third_key` from cache
      end
    end
  end

  # Workaround for Ruby VM < 3.2.8, < 3.3.8 and < 3.4.3 (see https://bugs.ruby-lang.org/issues/21170)
  context 'with a cache key with a #hash of -1 and a cache promotion to st_table' do
    let(:cache_limit) { 200 }
    let(:resolver_class) do
      Class.new(Datadog::Tracing::Contrib::Configuration::Resolver) do
        prepend Datadog::Tracing::Contrib::Configuration::CachingResolver
        attr_reader :cache

        def resolve(input)
          input.hash
        end
      end
    end

    subject(:cache) do
      key_class = Class.new do
        attr_reader :hash

        def initialize(hash_value)
          @hash = hash_value
        end
      end

      # 9 elements guarantees that the @cache hash does not fit in a
      # ar_table in both 32 and 64-bit MRI builds.
      0.downto(-8).each { |hash_value| resolver.resolve(key_class.new(hash_value)) }

      resolver.cache
    end

    it 'does not corrupt the cache' do
      expect(cache.keys.size).to eq(cache.size)
    end
  end
end
