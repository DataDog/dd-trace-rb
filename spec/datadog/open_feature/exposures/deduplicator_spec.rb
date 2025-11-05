# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/exposures'

RSpec.describe Datadog::OpenFeature::Exposures::Deduplicator do
  subject(:deduplicator) { described_class.new(limit: 2) }

  describe '#duplicate?' do
    context 'when exposure was never seen' do
      it 'returns false and stores digest' do
        expect(
          deduplicator.duplicate?('flag', 'user', allocation_key: 'alloc', variation_key: 'variant')
        ).to be(false)
      end
    end

    context 'when exposure was already reported' do
      before do
        deduplicator.duplicate?('flag', 'user', allocation_key: 'alloc', variation_key: 'variant')
      end

      it 'returns true for cached digest' do
        expect(
          deduplicator.duplicate?('flag', 'user', allocation_key: 'alloc', variation_key: 'variant')
        ).to be(true)
      end
    end

    context 'when variation key changes' do
      before do
        deduplicator.duplicate?('flag', 'user', allocation_key: 'alloc', variation_key: 'variant')
      end

      it 'returns false for different variation key' do
        expect(
          deduplicator.duplicate?('flag', 'user', allocation_key: 'alloc', variation_key: 'other')
        ).to be(false)
      end
    end

    context 'when allocation key changes' do
      before do
        deduplicator.duplicate?('flag', 'user', allocation_key: 'alloc', variation_key: 'variant')
      end

      it 'returns false for different allocation key' do
        expect(
          deduplicator.duplicate?('flag', 'user', allocation_key: 'other', variation_key: 'variant')
        ).to be(false)
      end
    end

    context 'when targeting key changes' do
      before do
        deduplicator.duplicate?('flag', 'user', allocation_key: 'alloc', variation_key: 'variant')
      end

      it 'returns false for different targeting key' do
        expect(
          deduplicator.duplicate?('flag', 'other', allocation_key: 'alloc', variation_key: 'variant')
        ).to be(false)
      end
    end

    context 'when cache evicts previous exposure' do
      before do
        deduplicator.duplicate?('flag-one', 'user', allocation_key: 'alloc', variation_key: 'variant')
        deduplicator.duplicate?('flag-two', 'user', allocation_key: 'alloc', variation_key: 'variant')
        deduplicator.duplicate?('flag-three', 'user', allocation_key: 'alloc', variation_key: 'variant')
      end

      it 'returns false after LRU eviction' do
        expect(
          deduplicator.duplicate?('flag-one', 'user', allocation_key: 'alloc', variation_key: 'variant')
        ).to be(false)
      end
    end
  end
end


