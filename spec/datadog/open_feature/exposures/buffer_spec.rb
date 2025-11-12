# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/exposures/buffer'

RSpec.describe Datadog::OpenFeature::Exposures::Buffer do
  describe '#push' do
    subject(:buffer) { described_class.new(1) }

    it 'drops items if maximum capacity is reached' do
      expect { buffer.push(:one) }.to change { buffer.length }.from(0).to(1)
      expect { buffer.push(:two) }.not_to change { buffer.length }.from(1)
      expect { buffer.push(:three) }.not_to change { buffer.length }.from(1)
    end
  end

  describe '#pop' do
    subject(:buffer) { described_class.new(1) }

    context 'when no items were dropped' do
      before { buffer.push(:one) }

      it 'returns the most recent items and sets dropped count' do
        expect(buffer.pop).to eq([:one])
        expect(buffer.dropped_count).to be_zero
      end

      it 'returns nothing and keeps resetted dropped count' do
        expect(buffer.pop).to eq([:one])
        expect(buffer.dropped_count).to be_zero

        expect(buffer.pop).to eq([])
        expect(buffer.dropped_count).to be_zero
      end
    end

    context 'when some items were dropped' do
      before do
        buffer.push(:one)
        buffer.push(:two)
        buffer.push(:three)
      end

      it 'returns the most recent items and dropped items counter' do
        expect(buffer.pop).to eq([:three])
        expect(buffer.dropped_count).to eq(2)
      end
    end
  end

  describe '#concat' do
    let(:buffer) { described_class.new(3) }

    context 'when total size does not exceed capacity' do
      it 'appends all items without dropping' do
        expect { buffer.concat([:one, :two]) }
          .to change { buffer.length }.from(0).to(2)

        expect(buffer.pop).to contain_exactly(:one, :two)
        expect(buffer.dropped_count).to be_zero
      end
    end

    context 'when total size exceeds capacity' do
      it 'drops overflow items and records drop count' do
        expect { buffer.concat([:one, :two, :three, :four, :five]) }
          .to change { buffer.length }.from(0).to(3)

        expect(buffer.pop.length).to eq(3)
        expect(buffer.dropped_count).to eq(2)
      end
    end
  end
end
