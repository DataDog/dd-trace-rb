require 'spec_helper'

require 'ddtrace/profiling/pprof/string_table'

RSpec.describe Datadog::Profiling::Pprof::StringTable do
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
