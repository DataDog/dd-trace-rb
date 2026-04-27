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

    context 'when a concurrent eviction happens during a hash key lookup' do
      let(:cache_limit) { 1 }
      let(:value) { :cached_value }
      let(:key) { cached_key }
      let(:cached_key) { comparable_value_class.new }
      let(:lookup_key) { comparable_value_class.new(lookup_started, continue_lookup) }
      let(:lookup_started) { Queue.new }
      let(:continue_lookup) { Queue.new }

      let(:comparable_value_class) do
        Class.new do
          def initialize(lookup_started = nil, continue_lookup = nil)
            @lookup_started = lookup_started
            @continue_lookup = continue_lookup
          end

          # Ruby Hash keys use #hash to select a bucket; returning the same
          # Integer forces Hash#key? to compare keys with #eql?.
          def hash
            1
          end

          def eql?(_other)
            if @lookup_started
              # Pause while Hash#key? is comparing the lookup key, so another
              # thread can try to evict the cache entry at the same time.
              @lookup_started << true
              @continue_lookup.pop
              @lookup_started = nil
            end

            true
          end
        end
      end

      it 'returns the cached value' do
        resolver.resolve(cached_key)

        # The lookup key is equivalent to the cached key and should return the
        # cached value even if a concurrent resolve attempts to evict the entry.
        lookup_thread = Thread.new { resolver.resolve(lookup_key) }
        lookup_started.pop

        evicting_thread = Thread.new { resolver.resolve(:evicting_key) }
        continue_lookup << true

        lookup_result = lookup_thread.value
        evicting_thread.join

        expect(lookup_result).to eq(:cached_value)
      end
    end
  end
end
