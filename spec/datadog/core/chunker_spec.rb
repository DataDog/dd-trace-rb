require 'spec_helper'

require 'datadog/core/chunker'

RSpec.describe Datadog::Core::Chunker do
  describe '.chunk_by_size' do
    subject(:chunk_by_size) { described_class.chunk_by_size(list, max_chunk_size) }

    let(:list) { %w[1 22 333] }
    let(:max_chunk_size) { 3 }

    it do
      expect(chunk_by_size.to_a).to eq([%w[1 22], ['333']])
    end

    context 'with single element that is too large' do
      let(:list) { ['55555'] }

      it 'returns single element exceeding maximum' do
        expect(chunk_by_size.to_a).to eq([['55555']])
      end
    end

    context 'with a lazy enumerator' do
      let(:list) { [].lazy }

      context 'with a runtime that correctly preserves the lazy enumerator' do
        before do
          if PlatformHelpers.jruby? && PlatformHelpers.engine_version < Gem::Version.new('9.2.9.0')
            skip 'This runtime returns eager enumerators on Enumerator::Lazy#slice_before calls'
          end
        end

        it 'does not force enumerator expansion' do
          expect(chunk_by_size).to be_a(Enumerator::Lazy)
        end
      end

      context 'with a runtime that erroneously loads the lazy enumerator eagerly' do
        before do
          if !PlatformHelpers.jruby? || PlatformHelpers.engine_version >= Gem::Version.new('9.2.9.0')
            skip 'This runtime correctly returns lazy enumerators on Enumerator::Lazy#slice_before calls'
          end
        end

        it do
          expect(chunk_by_size).to be_a(Enumerator)
        end
      end
    end
  end
end
