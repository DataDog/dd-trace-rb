# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/api_security/lru_cache'

RSpec.describe Datadog::AppSec::APISecurity::LRUCache do
  describe '#initialize' do
    it { expect(described_class.new(3)).to be_empty }
    it { expect { described_class.new('0') }.to raise_error(ArgumentError) }
    it { expect { described_class.new(0) }.to raise_error(ArgumentError) }
    it { expect { described_class.new(-1) }.to raise_error(ArgumentError) }
  end

  describe '#[]' do
    let(:lru_cache) { described_class.new(3) }

    context 'when key does not exist' do
      it { expect(lru_cache[:missing_key]).to be_nil }
    end

    context 'when key exists' do
      before { lru_cache.fetch_or_store(:key) { 'value' } }

      it { expect(lru_cache[:key]).to eq('value') }
    end

    context 'when key exists and is accessed' do
      it 'updates the key order' do
        lru_cache.fetch_or_store(:key1) { 'value1' }
        lru_cache.fetch_or_store(:key2) { 'value2' }
        lru_cache.fetch_or_store(:key3) { 'value3' }

        lru_cache[:key1] # NOTE: as key accessed, it's moved to the end of the list
        lru_cache.fetch_or_store(:key4) { 'value4' }

        aggregate_failures 'verifying LRU cache state after key access and eviction' do
          expect(lru_cache[:key2]).to be_nil
          expect(lru_cache[:key1]).to eq('value1')
          expect(lru_cache[:key3]).to eq('value3')
          expect(lru_cache[:key4]).to eq('value4')
        end
      end
    end
  end

  describe '#store' do
    let(:lru_cache) { described_class.new(3) }

    it 'stores a key-value pair' do
      expect { lru_cache.store(:key, 'value') }.to change { lru_cache[:key] }
        .from(nil).to('value')
    end

    it 'overwrites existing values' do
      lru_cache.store(:key, 'old-value')

      expect { lru_cache.store(:key, 'new-value') }.to change { lru_cache[:key] }
        .from('old-value').to('new-value')
    end

    context 'when maximum size is reached' do
      it 'evicts the least recently used item' do
        lru_cache.store(:key1, 'value1')
        lru_cache.store(:key2, 'value2')
        lru_cache.store(:key3, 'value3')
        lru_cache.store(:key4, 'value4')

        aggregate_failures 'verifying LRU cache state after eviction' do
          expect(lru_cache[:key1]).to be_nil
          expect(lru_cache[:key2]).to eq('value2')
          expect(lru_cache[:key3]).to eq('value3')
          expect(lru_cache[:key4]).to eq('value4')
        end
      end
    end
  end

  describe '#fetch_or_store' do
    context 'when key does not exist' do
      let(:lru_cache) { described_class.new(3) }

      it 'computes and stores the value' do
        expect(lru_cache.fetch_or_store(:key) { 'value' }).to eq('value')
        expect(lru_cache[:key]).to eq('value')
      end

      it 'computes the missing key only once' do
        expect { lru_cache.fetch_or_store(:key) { 'value' } }
          .to change { lru_cache[:key] }.from(nil).to('value')

        expect { lru_cache.fetch_or_store(:key) { 'new-value' } }
          .not_to(change { lru_cache[:key] })
      end
    end

    context 'when maximum size is reached' do
      let(:lru_cache) { described_class.new(3) }

      it 'evicts the least recently used item' do
        lru_cache.fetch_or_store(:key1) { 'value1' }
        lru_cache.fetch_or_store(:key2) { 'value2' }
        lru_cache.fetch_or_store(:key3) { 'value3' }
        lru_cache.fetch_or_store(:key4) { 'value4' }

        aggregate_failures 'verifying LRU cache state after eviction' do
          expect(lru_cache[:key1]).to be_nil
          expect(lru_cache[:key2]).to eq('value2')
          expect(lru_cache[:key3]).to eq('value3')
          expect(lru_cache[:key4]).to eq('value4')
        end
      end
    end
  end

  describe '#clear' do
    let(:lru_cache) { described_class.new(3) }

    it 'removes all items from the cache' do
      lru_cache.fetch_or_store(:key1) { 'value1' }
      lru_cache.fetch_or_store(:key2) { 'value2' }

      expect { lru_cache.clear }.to change { lru_cache[:key1] }.from('value1').to(nil)
        .and change { lru_cache[:key2] }.from('value2').to(nil)
        .and change { lru_cache.empty? }.from(false).to(true)
    end
  end

  describe '#empty?' do
    let(:lru_cache) { described_class.new(3) }

    it 'returns false when cache has items' do
      expect { lru_cache.fetch_or_store(:key) { 'value' } }
        .to change { lru_cache.empty? }.from(true).to(false)
    end
  end
end
