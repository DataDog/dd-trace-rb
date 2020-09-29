require 'spec_helper'

require 'ddtrace'
require 'ddtrace/distributed_tracing/headers/helpers'
require 'ddtrace/span'

RSpec.describe Datadog::DistributedTracing::Headers::Helpers do
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

  describe '#truncate_base16_number' do
    subject(:number) { described_class.truncate_base16_number(value) }

    [
      %w[1 1],

      # Test removing leading zeros
      %w[0 0],
      %w[000000 0],
      %w[000001 1],
      %w[000010 10],

      # Test lowercase
      %w[DEADBEEF deadbeef],

      # Test at boundary (64-bit)
      # 64-bit max, which is 17 characters long, so we truncate to the last 16, which is all zeros
      [(2**64).to_s(16), '0'],
      # 64-bit - 1, which is the max 16 characters we allow
      [((2**64) - 1).to_s(16), 'ffffffffffffffff'],

      # Our max generated id
      [Datadog::Span::RUBY_MAX_ID.to_s(16), '3fffffffffffffff'],
      # Our max external id
      # DEV: This is the same as (2**64) above, but use the constant to be sure
      [Datadog::Span::EXTERNAL_MAX_ID.to_s(16), '0'],

      # 128-bit max, which is 32 characters long, so we truncate to the last 16, which is all zeros
      [(2**128).to_s(16), '0'],
      # 128-bit - 1, which is 32 characters long and all `f`s
      [((2**128) - 1).to_s(16), 'ffffffffffffffff']
    ].each do |value, expected|
      context "with input of #{value}" do
        let(:value) { value }
        it { is_expected.to eq(expected) }
      end
    end
  end
end
