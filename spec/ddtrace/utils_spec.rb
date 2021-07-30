require 'concurrent-ruby'

RSpec.describe Datadog::Utils do
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

  describe '.truncate' do
    subject(:truncate) { described_class.truncate(value, size, omission) }
    let(:value) { 123456 }
    let(:omission) { '...' }

    context 'the stringified value fits in size' do
      let(:size) { 6 }

      it 'returns the stringified value' do
        is_expected.to eq('123456')
      end
    end

    context 'the stringified value does not fits in size' do
      let(:size) { 5 }

      it 'returns the stringified value prefix with the omission as a suffix' do
        is_expected.to eq('12...')
      end

      context 'omission is larger than size' do
        let(:size) { 1 }

        it 'still returns the complete omission suffix' do
          is_expected.to eq('...')
        end
      end
    end

    context 'with nil' do
      let(:value) { nil }
      let(:size) { 1 }

      it 'returns an empty string' do
        is_expected.to eq('')
      end
    end
  end

  describe '.utf8_encode' do
    subject(:utf8_encode) { described_class.utf8_encode(str, **options) }
    let(:options) { {} }

    context 'with valid UTF-8 string' do
      let(:str) { 'ᕕ(ᐛ)ᕗ'.encode(Encoding::UTF_8) }

      it 'returns the same object' do
        is_expected.to be(str)
      end
    end

    context 'with nil' do
      let(:str) { nil }

      it 'return an empty string' do
        is_expected.to eq('')
      end

      # Only TruffleRuby returns an UTF-8 string for `nil.to_s` today.
      it 'does not allocate a new empty string', if: nil.to_s.encoding == Encoding::UTF_8 do
        is_expected.to be(nil.to_s)
      end

      # Other implementations return an ASCII string.
      it 'does not allocate a new empty string', if: nil.to_s.encoding != Encoding::UTF_8 do
        is_expected.to be(Datadog::Utils::EMPTY_STRING)
      end
    end

    context 'with an invalid string' do
      let(:str) { "valid\xC2 part".force_encoding(Encoding::ASCII_8BIT) }

      it 'return an empty string' do
        is_expected.to eq(Datadog::Utils::EMPTY_STRING)
      end

      context 'with a placeholder' do
        let(:options) { { placeholder: '_?_' } }

        it 'returns the placeholder' do
          is_expected.to eq('_?_')
        end
      end

      context 'in binary mode' do
        let(:options) { { binary: true } }

        it 'keeps the valid part' do
          is_expected.to eq('valid part')
        end
      end
    end
  end
end
