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
