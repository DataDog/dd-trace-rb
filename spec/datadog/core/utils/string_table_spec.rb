require 'spec_helper'

require 'datadog/core/utils/string_table'

RSpec.describe Datadog::Core::Utils::StringTable do
  subject(:string_table) { described_class.new }

  describe '#fetch' do
    subject(:fetch) { string_table.fetch(string) }

    context 'given an empty string' do
      let(:string) { '' }

      it { is_expected.to be 0 }
    end

    context 'given different strings' do
      it 'returns different IDs' do
        3.times do |i|
          expect(string_table.fetch(i.to_s)).to be(i + 1)
        end
      end
    end

    context 'given the same string' do
      let(:string) { 'foo' }

      it 'returns the same ID' do
        is_expected.to be 1

        3.times do
          expect(string_table.fetch(string)).to be(1)
        end
      end
    end
  end

  describe '#fetch_string' do
    subject(:fetch_string) { string_table.fetch_string(string) }

    let(:string) { 'string' }

    it { is_expected.to eq(string) }

    it 'returns the same string object' do
      strings = []
      strings << string_table.fetch_string(string)
      strings << string_table.fetch_string(string)
      strings << string_table.fetch_string(string.dup)

      expect(strings.collect(&:object_id).uniq).to have(1).item
    end
  end

  describe '#[]' do
    subject(:get_string) { string_table[id] }

    context 'when ID doesn\'t exist in the string table' do
      let(:id) { double('unknown ID') }

      it { is_expected.to be nil }
    end

    context 'when the ID exsits in the string table' do
      let(:string) { 'string' }
      let(:id) { string_table.fetch(string) }

      it { is_expected.to eq(string) }
    end
  end

  describe '#strings' do
    subject(:strings) { string_table.strings }

    context 'when IDs have been added' do
      before do
        string_table.fetch('foo')
        string_table.fetch('bar')
        string_table.fetch('bar')
      end

      it 'returns all the unique strings' do
        is_expected.to eq(['', 'foo', 'bar'])
      end
    end
  end
end
