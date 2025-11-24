# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/exposures/deduplicator'

RSpec.describe Datadog::OpenFeature::Exposures::Deduplicator do
  subject(:deduplicator) { described_class.new(limit: 2) }

  describe '#duplicate?' do
    context 'when exposure was never seen' do
      it { expect(deduplicator.duplicate?('flag:user', 'alloc:variant')).to be(false) }
    end

    context 'when exposure was already reported' do
      before { deduplicator.duplicate?('flag:user', 'alloc:variant') }

      it { expect(deduplicator.duplicate?('flag:user', 'alloc:variant')).to be(true) }
    end

    context 'when variation key changes' do
      before { deduplicator.duplicate?('flag:user', 'alloc:variant') }

      it { expect(deduplicator.duplicate?('flag:user', 'alloc:other')).to be(false) }
    end

    context 'when allocation key changes' do
      before { deduplicator.duplicate?('flag:user', 'alloc:variant') }

      it { expect(deduplicator.duplicate?('flag:user', 'other:variant')).to be(false) }
    end

    context 'when targeting key changes' do
      before { deduplicator.duplicate?('flag:user', 'alloc:variant') }

      it { expect(deduplicator.duplicate?('flag:other', 'alloc:variant')).to be(false) }
    end

    context 'when cache evicts previous exposure' do
      before do
        deduplicator.duplicate?('flag-one:user', 'alloc:variant')
        deduplicator.duplicate?('flag-two:user', 'alloc:variant')
        deduplicator.duplicate?('flag-three:user', 'alloc:variant')
      end

      it 'returns false after LRU eviction and true when cached' do
        expect(deduplicator.duplicate?('flag-one:user', 'alloc:variant')).to be(false)
        expect(deduplicator.duplicate?('flag-one:user', 'alloc:variant')).to be(true)
      end
    end
  end
end
