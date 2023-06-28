require 'spec_helper'

require 'datadog/core/utils/sequence'

RSpec.describe Datadog::Core::Utils::Sequence do
  describe '#next' do
    context 'for a sequence' do
      context 'with default settings' do
        let(:sequence) { described_class.new }

        it 'produces an integer sequence' do
          expect(sequence.next).to eq 0
          expect(sequence.next).to eq 1
          expect(sequence.next).to eq 2
        end
      end

      context 'with a seed' do
        let(:sequence) { described_class.new(seed) }
        let(:seed) { 10 }

        it 'produces an integer sequence starting at the seed' do
          expect(sequence.next).to eq 10
          expect(sequence.next).to eq 11
          expect(sequence.next).to eq 12
        end
      end

      context 'with a block' do
        let(:sequence) { described_class.new(&block) }
        let(:block) { ->(i) { i.to_s } }

        it 'returns the block value for each iteration' do
          expect(sequence.next).to eq '0'
          expect(sequence.next).to eq '1'
          expect(sequence.next).to eq '2'
        end
      end
    end
  end

  describe '#reset!' do
    context 'for a sequence' do
      context 'with default settings' do
        let(:sequence) { described_class.new }

        it 'produces an integer sequence' do
          expect(sequence.next).to eq 0
          sequence.reset!
          expect(sequence.next).to eq 0
        end
      end

      context 'with a seed' do
        let(:sequence) { described_class.new(seed) }
        let(:seed) { 10 }

        it 'produces an integer sequence starting at the seed' do
          expect(sequence.next).to eq 10
          sequence.reset!
          expect(sequence.next).to eq 10
        end
      end

      context 'with a block' do
        let(:sequence) { described_class.new(&block) }
        let(:block) { ->(i) { i.to_s } }

        it 'returns the block value for each iteration' do
          expect(sequence.next).to eq '0'
          sequence.reset!
          expect(sequence.next).to eq '0'
        end
      end
    end
  end
end
