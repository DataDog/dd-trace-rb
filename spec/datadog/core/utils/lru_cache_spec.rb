# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/utils/lru_cache'

RSpec.describe Datadog::Core::Utils::LRUCache do
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
      before { lru_cache[:key] = 'value' }

      it { expect(lru_cache[:key]).to eq('value') }
    end

    context 'when key exists and is accessed' do
      it 'updates the key order' do
        lru_cache[:key1] = 'value1'
        lru_cache[:key2] = 'value2'
        lru_cache[:key3] = 'value3'

        lru_cache[:key1] # NOTE: as key accessed, it's moved to the end of the list
        lru_cache[:key4] = 'value4'

        aggregate_failures 'verifying LRU cache state after key access and eviction' do
          expect(lru_cache[:key2]).to be_nil
          expect(lru_cache[:key1]).to eq('value1')
          expect(lru_cache[:key3]).to eq('value3')
          expect(lru_cache[:key4]).to eq('value4')
        end
      end
    end
  end

  describe '#[]=' do
    let(:lru_cache) { described_class.new(3) }

    it 'stores a key-value pair' do
      expect { lru_cache[:key] = 'value' }.to change { lru_cache[:key] }
        .from(nil).to('value')
    end

    it 'overwrites existing values' do
      lru_cache[:key] = 'old-value'

      expect { lru_cache[:key] = 'new-value' }.to change { lru_cache[:key] }
        .from('old-value').to('new-value')
    end

    context 'when cache is full and an existing key is updated' do
      it 'does not remove other entries' do
        lru_cache[:key2] = 'value2'
        lru_cache[:key3] = 'value3'
        lru_cache[:key1] = 'value1'

        lru_cache[:key1] = 'new-value1'
        lru_cache[:key3] = 'new-value3'
        lru_cache[:key2] = 'new-value2'

        aggregate_failures 'verifying LRU cache contents' do
          expect(lru_cache[:key1]).to eq('new-value1')
          expect(lru_cache[:key2]).to eq('new-value2')
          expect(lru_cache[:key3]).to eq('new-value3')
        end
      end
    end

    context 'when maximum size is reached' do
      it 'evicts the least recently used item' do
        lru_cache[:key1] = 'value1'
        lru_cache[:key2] = 'value2'
        lru_cache[:key3] = 'value3'
        lru_cache[:key4] = 'value4'

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
      lru_cache[:key1] = 'value1'
      lru_cache[:key2] = 'value2'

      expect { lru_cache.clear }.to change { lru_cache[:key1] }.from('value1').to(nil)
        .and change { lru_cache[:key2] }.from('value2').to(nil)
        .and change { lru_cache.empty? }.from(false).to(true)
    end
  end

  describe '#empty?' do
    let(:lru_cache) { described_class.new(3) }

    it 'returns false when cache has items' do
      expect { lru_cache[:key] = 'value' }
        .to change { lru_cache.empty? }.from(true).to(false)
    end
  end
end
