require 'spec_helper'
require 'spec/support/language_helpers'

require 'ddtrace/chunker'

RSpec.describe Datadog::Chunker do
  context '.chunk_by_size' do
    subject(:encode) { described_class.chunk_by_size(list, max_chunk_size) }
    let(:list) { %w[1 22 333] }
    let(:max_chunk_size) { 3 }

    it do
      expect(subject.to_a).to eq([%w[1 22], ['333']])
    end

    context 'with single element that is too large' do
      let(:list) { ['55555'] }

      it 'returns single element exceeding maximum' do
        expect(subject.to_a).to eq([['55555']])
      end
    end

    context 'with a lazy enumerator' do
      let(:list) { [].lazy }

      it 'does not force enumerator expansion' do
        expect(subject).to be_a(Enumerator::Lazy)
      end
    end
  end
end
