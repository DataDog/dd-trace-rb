require 'spec_helper'
require 'datadog/core/utils/fnv'

RSpec.describe Datadog::Core::Utils::FNV do
  describe '.fnv1_64' do
    it 'computes the correct hash for an empty string' do
      expect(described_class.fnv1_64('')).to eq(14695981039346656037)
    end

    it 'gives the same hash for the same string' do
      expect(described_class.fnv1_64('hello')).to eq(described_class.fnv1_64('hello'))
    end

    it 'gives different hash for different strings' do
      expect(described_class.fnv1_64('hello')).not_to eq(described_class.fnv1_64('hello1'))
    end
  end
end
