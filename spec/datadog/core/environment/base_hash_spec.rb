require 'spec_helper'
require 'datadog/core/environment/base_hash'

RSpec.describe Datadog::Core::Environment::BaseHash do
  before { described_class.reset! }
  after { described_class.reset! }

  describe '.compute' do
    let(:container_hash) { '1234567890' }
    let(:process_tags) { 'entrypoint.workdir:myapp,entrypoint.name:rails' }

    before do
      allow(Datadog::Core::Environment::Process).to receive(:serialized).and_return(process_tags)
    end

    it 'returns an integer hash' do
      result = described_class.compute(container_hash)
      expect(result).to be_a(Integer)
    end

    it 'computes different hashes for different strings' do
      result1 = described_class.compute('string1')
      result2 = described_class.compute('string2')
      expect(result1).not_to eq(result2)
    end

    it 'includes both process tags and container tags in the resulting hash' do
      result = described_class.compute(container_hash)

      expected_data = process_tags + container_hash
      expected_hash = Datadog::Core::Utils::FNV.fnv1_64(expected_data)
      expect(result).to eq(expected_hash)
    end

    it 'caches the computed hash if the container hash is the same' do
      hash1 = described_class.compute(container_hash)
      hash2 = described_class.compute(container_hash)

      expect(hash1).to eq(hash2)
      expect(Datadog::Core::Environment::Process).to have_received(:serialized).once
    end
  end

  describe '.current' do
    it 'returns nil when no hash was computed' do
      expect(described_class.current).to be nil
    end

    it 'returns the last computed hash' do
      expected_hash = described_class.compute('randomstring')
      expect(described_class.current).to eq(expected_hash)
    end
  end
end
