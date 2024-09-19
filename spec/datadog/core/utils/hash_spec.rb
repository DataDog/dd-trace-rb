require 'spec_helper'

require 'datadog/core/utils/hash'

RSpec.describe Datadog::Core::Utils::Hash::CaseInsensitiveWrapper do
  subject(:wrapper) { described_class.new(hash) }

  context 'for a populated hash' do
    let(:hash) { { 'lower' => 'lower_value', 'UPPER' => 'upper_value', non_string_key: 'oops' } }

    {
      'lower' => 'lower_value',
      'LoWeR' => 'lower_value',
      'UPPER' => 'upper_value',
      'uPpEr' => 'upper_value',
      non_string_key: nil,
    }.each do |key, expected_value|
      context "for key #{key.inspect}" do
        let(:key) { key }

        context 'and #[]' do
          it "returns #{expected_value.inspect}" do
            expect(wrapper[key]).to eq(expected_value)
          end
        end

        context 'and #key?' do
          it "returns #{!expected_value.nil?}" do
            expect(wrapper.key?(key)).to eq(!expected_value.nil?)
          end
        end
      end
    end

    it '#original_hash returns the initialize argument' do
      expect(wrapper.original_hash).to be(hash)
    end

    it '#length returns the length of the original hash' do
      expect(wrapper.length).to eq(3)
    end

    it '#empty? returns false' do
      expect(wrapper.empty?).to eq(false)
    end
  end

  context 'for an empty hash' do
    let(:hash) { {} }

    it '#length returns the length of the original hash' do
      expect(wrapper.length).to eq(0)
    end

    it '#empty? returns true' do
      expect(wrapper.empty?).to eq(true)
    end
  end

  context 'for a non-hash' do
    let(:hash) { [] }

    it 'errors on initialize' do
      expect { wrapper }.to raise_error(ArgumentError)
    end
  end
end
