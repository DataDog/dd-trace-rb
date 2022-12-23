# typed: false

require 'spec_helper'

require 'datadog/tracing/utils'

RSpec.describe Datadog::Tracing::Utils do
  describe '.next_id' do
    subject(:next_id) { described_class.next_id }

    it 'returns a positive integer smaller than 2**62' do
      is_expected.to be_a(Integer)
      is_expected.to be_between(1, 2**62 - 1)
    end

    it 'fits in a CRuby VALUE slot', if: ObjectSpaceHelper.estimate_bytesize_supported? do
      expect(ObjectSpaceHelper.estimate_bytesize(next_id)).to eq(0)
    end

    it 'returns unique numbers on successive calls' do
      is_expected.to_not eq(described_class.next_id)
    end

    context 'after forking', if: PlatformHelpers.supports_fork? do
      it 'generates unique ids across forks' do
        ids = Array.new(3) do
          result = expect_in_fork { puts next_id }
          Integer(result[:stdout])
        end.uniq

        expect(ids).to have(3).items
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Utils::TraceId do
  describe '.to_low_order' do
    context 'when given <= 64 bit' do
      [
        0xaaaaaaaaaaaaaaaa,
        0xffffffffffffffff
      ].each do |input|
        it 'returns itself' do
          expect(input.bit_length).to be <= 64
          expect(described_class.to_low_order(input)).to eq(input)
        end
      end
    end

    context 'when given > 64 bit' do
      {
        0xffffffffffffffffaaaaaaaaaaaaaaaa => 0xaaaaaaaaaaaaaaaa,
        0xaaaaaaaaaaaaaaaaffffffffffffffff => 0xffffffffffffffff,
      }.each do |input, result|
        context "when given `0x#{input.to_s(16)}`" do
          it "returns the lower order 64 bits `0x#{result.to_s(16)}`" do
            expect(input.bit_length).to be > 64
            expect(described_class.to_low_order(input)).to eq(result)
          end
        end
      end
    end
  end

  describe '.to_high_order' do
    context 'when given <= 64 bit' do
      [
        0xaaaaaaaaaaaaaaaa,
        0xffffffffffffffff
      ].each do |input|
        it 'returns 0' do
          expect(input.bit_length).to be <= 64
          expect(described_class.to_high_order(input)).to eq(0)
        end
      end
    end

    context 'when given > 64 bit' do
      {
        0xffffffffffffffffaaaaaaaaaaaaaaaa => 0xffffffffffffffff,
        0xaaaaaaaaaaaaaaaaffffffffffffffff => 0xaaaaaaaaaaaaaaaa,
      }.each do |input, result|
        context "when given `0x#{input.to_s(16)}`" do
          it "returns the lower order 64 bits `0x#{result.to_s(16)}`" do
            expect(input.bit_length).to be > 64
            expect(described_class.to_high_order(input)).to eq(result)
          end
        end
      end
    end
  end

  describe '.concatenate' do
    {
      [0xaaaaaaaaaaaaaaaa, 0xffffffffffffffff] => 0xaaaaaaaaaaaaaaaaffffffffffffffff,
      [0xffffffffffffffff, 0xaaaaaaaaaaaaaaaa] => 0xffffffffffffffffaaaaaaaaaaaaaaaa,
      [0x00000000aaaaaaaa, 0xffffffffffffffff] => 0x00000000aaaaaaaaffffffffffffffff,
      [0xaaaaaaaaaaaaaaaa, 0xffffffff] => 0xaaaaaaaaaaaaaaaa00000000ffffffff,
    }.each do |(high_order, low_order), result|
      context "when given `0x#{high_order.to_s(16)}` and `0x#{low_order.to_s(16)}`" do
        it "returns `0x#{result.to_s(16)}`" do
          expect(described_class.concatenate(high_order, low_order)).to eq(result)
        end
      end
    end
  end
end
