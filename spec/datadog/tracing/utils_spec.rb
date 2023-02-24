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
