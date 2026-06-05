require 'spec_helper'

require 'datadog/tracing/distributed/helpers'
require 'datadog/tracing/utils'

RSpec.describe Datadog::Tracing::Distributed::Helpers do
  describe '#clamp_sampling_priority' do
    subject(:sampling_priority) { described_class.clamp_sampling_priority(value) }

    [
      [-1, 0],
      [0, 0],
      [1, 1],
      [2, 1]
    ].each do |value, expected|
      context "with input of #{value}" do
        let(:value) { value }

        it { is_expected.to eq(expected) }
      end
    end
  end

  describe '.parse_decimal_id' do
    [
      [nil, nil],
      ['', nil],
      ['not a number', nil],
      ['1 2', nil], # "1 2".to_i => 1, but it's an invalid format
      ['1.2', nil],
      ['0', 0],
      ['1', 1],
      ['-1', -1],
      ['123456789', 123456789],
    ].each do |value, expected|
      context "when given #{value.inspect}" do
        it { expect(described_class.parse_decimal_id(value)).to eq(expected) }
      end
    end
  end

  describe '.normalize_tracestate_encoding' do
    subject(:result) { described_class.normalize_tracestate_encoding(value) }

    context 'with nil' do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context 'with an empty string tagged ASCII-8BIT' do
      let(:value) { String.new('', encoding: Encoding::ASCII_8BIT) }

      it 'returns an empty UTF-8 string' do
        expect(result).to eq('')
        expect(result.encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'with an ASCII-8BIT string containing only ASCII bytes' do
      let(:value) { String.new('vendor1=value1,vendor2=value2', encoding: Encoding::ASCII_8BIT) }

      it 'retags as UTF-8 without modifying bytes' do
        expect(result).to eq('vendor1=value1,vendor2=value2')
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.bytes).to eq(value.bytes)
      end

      it 'does not mutate the input' do
        expect { result }.not_to(change { value.encoding })
      end
    end

    context 'with a UTF-8 string that is already valid' do
      let(:value) { 'vendor1=value1' }

      it 'returns the input unchanged' do
        expect(result).to equal(value)
      end
    end

    context 'with an ASCII-8BIT string whose bytes form a valid UTF-8 sequence' do
      # 'café' in UTF-8 is 63 61 66 c3 a9
      let(:value) { String.new("caf\xC3\xA9", encoding: Encoding::ASCII_8BIT) }

      it 'returns a UTF-8 string with the same bytes' do
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.bytes).to eq(value.bytes)
      end
    end

    context 'with an ASCII-8BIT string containing invalid UTF-8 byte sequences' do
      # Lone 0xFF is not a valid UTF-8 start byte.
      let(:value) { String.new("foo\xFFbar", encoding: Encoding::ASCII_8BIT) }

      it { is_expected.to be_nil }
    end

    context 'with a frozen ASCII-8BIT string' do
      let(:value) { String.new('vendor=value', encoding: Encoding::ASCII_8BIT).freeze }

      it 'returns a UTF-8 string without raising' do
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq('vendor=value')
      end
    end
  end

  describe '.parse_hex_id' do
    context 'when given with `length`' do
      [
        [nil, nil],
        ['', nil],
        ['not a number', nil],
        ['1 2', nil], # "1 2".to_i => 1, but it's an invalid format
        ['1.2', nil],
        ['0', 0],
        ['1', 1],
        ['-1', -1],
        ['123456789', 0x123456789],
        ['abcdef', 0xabcdef], # lower case
        ['ABCDEF', 0xabcdef], # upper case
        ['00123456789', 0x123456789], # leading zeros
        ['000abcdef', 0xabcdef], # leading zeros
        ['000ABCDEF', 0xabcdef], # leading zeros
        ['aaaaaaaaaaaaaaaaffffffffffffffff', 0xaaaaaaaaaaaaaaaaffffffffffffffff], # 128 bits
        ['ffffffffffffffff', 0xffffffffffffffff], # 64 bits
      ].each do |value, expected|
        context "when given #{value.inspect}" do
          it { expect(described_class.parse_hex_id(value)).to eq(expected) }
        end
      end
    end
  end
end
