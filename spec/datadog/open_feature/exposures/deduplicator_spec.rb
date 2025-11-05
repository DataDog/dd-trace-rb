# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/exposures/deduplicator'

RSpec.describe Datadog::OpenFeature::Exposures::Deduplicator do
  subject(:deduplicator) { described_class.new(limit: 2) }

  describe '#duplicate?' do
    context 'when exposure was never seen' do
      let(:event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag',
          targeting_key: 'user',
          allocation_key: 'alloc',
          variation_key: 'variant'
        )
      end

      it { expect(deduplicator.duplicate?(event)).to be(false) }
    end

    context 'when exposure was already reported' do
      before { deduplicator.duplicate?(event) }

      let(:event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag',
          targeting_key: 'user',
          allocation_key: 'alloc',
          variation_key: 'variant'
        )
      end


      it { expect(deduplicator.duplicate?(event)).to be(true) }
    end

    context 'when variation key changes' do
      before { deduplicator.duplicate?(original_event) }

      let(:original_event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag',
          targeting_key: 'user',
          allocation_key: 'alloc',
          variation_key: 'variant'
        )
      end

      let(:changed_event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag',
          targeting_key: 'user',
          allocation_key: 'alloc',
          variation_key: 'other'
        )
      end

      it { expect(deduplicator.duplicate?(changed_event)).to be(false) }
    end

    context 'when allocation key changes' do
      before { deduplicator.duplicate?(original_event) }

      let(:original_event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag',
          targeting_key: 'user',
          allocation_key: 'alloc',
          variation_key: 'variant'
        )
      end

      let(:changed_event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag',
          targeting_key: 'user',
          allocation_key: 'other',
          variation_key: 'variant'
        )
      end

      it { expect(deduplicator.duplicate?(changed_event)).to be(false) }
    end

    context 'when targeting key changes' do
      before { deduplicator.duplicate?(original_event) }

      let(:original_event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag',
          targeting_key: 'user',
          allocation_key: 'alloc',
          variation_key: 'variant'
        )
      end

      let(:changed_event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag',
          targeting_key: 'other',
          allocation_key: 'alloc',
          variation_key: 'variant'
        )
      end

      before { deduplicator.duplicate?(original_event) }

      it { expect(deduplicator.duplicate?(changed_event)).to be(false) }
    end

    context 'when cache evicts previous exposure' do
      before do
        deduplicator.duplicate?(first_event)
        deduplicator.duplicate?(second_event)
        deduplicator.duplicate?(third_event)
      end

      let(:first_event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag-one',
          targeting_key: 'user',
          allocation_key: 'alloc',
          variation_key: 'variant'
        )
      end

      let(:second_event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag-two',
          targeting_key: 'user',
          allocation_key: 'alloc',
          variation_key: 'variant'
        )
      end

      let(:third_event) do
        instance_double(
          Datadog::OpenFeature::Exposures::Models::Event,
          flag_key: 'flag-three',
          targeting_key: 'user',
          allocation_key: 'alloc',
          variation_key: 'variant'
        )
      end

      it 'returns false after LRU eviction and true when cached' do
        expect(deduplicator.duplicate?(first_event)).to be(false)
        expect(deduplicator.duplicate?(first_event)).to be(true)
      end
    end
  end
end


