require 'datadog/core/utils/safe_dup'

RSpec.describe Datadog::Core::Utils::SafeDup do
  context 'String' do
    describe '.frozen_or_dup' do
      context 'when given a frozen string' do
        it 'returns the original input' do
          input = 'a_frozen_string'.freeze

          result = described_class.frozen_or_dup(input)

          expect(input).to be_frozen

          expect(result).to be(input)
          expect(result).to be_frozen
        end
      end

      context 'when given a string' do
        it 'returns a non-frozen dupliacte' do
          input = 'a_string'

          result = described_class.frozen_or_dup(input)

          expect(input).not_to be_frozen

          expect(result).to eq(input)
          expect(result).not_to be(input)
          expect(result).not_to be_frozen
        end
      end
    end

    describe '.frozen_dup' do
      context 'when given a frozen string' do
        it 'returns the original input' do
          input = 'a_frozen_string'.freeze

          result = described_class.frozen_dup(input)

          expect(input).to be_frozen

          expect(result).to be(input)
          expect(result).to be_frozen
        end
      end

      context 'when given a string' do
        it 'returns a frozen duplicate' do
          input = 'a_string'

          result = described_class.frozen_dup(input)

          expect(input).not_to be_frozen

          expect(result).to eq(input)
          expect(result).not_to be(input)
          expect(result).to be_frozen
        end
      end
    end
  end

  context 'Hash' do
    describe '.frozen_or_dup' do
      context 'when given a frozen hash' do
        it 'returns the original input' do
          input = { a: :b }.freeze

          result = described_class.frozen_or_dup(input)

          expect(input).to be_frozen

          expect(result).to be(input)
          expect(result).to be_frozen
        end
      end

      context 'when given a hash' do
        it 'returns a non-frozen dupliacte' do
          input = { a: :b }

          result = described_class.frozen_or_dup(input)

          expect(input).not_to be_frozen

          expect(result).to eq(input)
          expect(result).not_to be(input)
          expect(result).not_to be_frozen
        end
      end
    end

    describe '.frozen_dup' do
      context 'when given a frozen hash' do
        it 'returns the original input' do
          input = { a: :b }.freeze

          result = described_class.frozen_dup(input)

          expect(input).to be_frozen

          expect(result).to be(input)
          expect(result).to be_frozen
        end
      end

      context 'when given a hash' do
        it 'returns a frozen duplicate' do
          input = { a: :b }

          result = described_class.frozen_dup(input)

          expect(input).not_to be_frozen

          expect(result).to eq(input)
          expect(result).not_to be(input)
          expect(result).to be_frozen
        end
      end
    end
  end

  context 'Boolean' do
    describe '.frozen_or_dup' do
      context 'when given a boolean' do
        it 'returns the original input' do
          input = true

          result = described_class.frozen_or_dup(input)

          expect(input).to be_frozen

          expect(result).to be(input)
          expect(result).to be_frozen
        end
      end
    end

    describe '.frozen_dup' do
      context 'when given a boolean' do
        it 'returns the original input' do
          input = true

          result = described_class.frozen_dup(input)

          expect(input).to be_frozen

          expect(result).to be(input)
          expect(result).to be_frozen
        end
      end
    end
  end

  context 'Array' do
    describe '.frozen_or_dup' do
      context 'when given a frozen array' do
        it 'returns the original input' do
          input = [1].freeze

          result = described_class.frozen_or_dup(input)

          expect(input).to be_frozen

          expect(result).to be(input)
          expect(result).to be_frozen
        end
      end

      context 'when given an array' do
        it 'returns a non-frozen copy of that array' do
          input = [1]

          result = described_class.frozen_or_dup(input)

          expect(input).not_to be_frozen

          expect(result).to eq(input)
          expect(result).not_to be(input)
          expect(result).not_to be_frozen
        end
      end
    end

    describe '.frozen_dup' do
      context 'when given a frozen array' do
        it 'returns the original input' do
          input = [1].freeze

          result = described_class.frozen_dup(input)

          expect(input).to be_frozen

          expect(result).to be(input)
          expect(result).to be_frozen
        end
      end

      context 'when given an array' do
        it 'returns a frozen duplicate' do
          input = [1]

          result = described_class.frozen_dup(input)

          expect(input).not_to be_frozen

          expect(result).to eq(input)
          expect(result).not_to be(input)
          expect(result).to be_frozen
        end
      end
    end
  end

  context 'Numeric' do
    describe '.frozen_or_dup' do
      context 'when given a numeric' do
        it 'returns the original input' do
          input = 1

          result = described_class.frozen_or_dup(input)

          expect(input).to be_frozen

          expect(result).to be(input)
          expect(result).to be_frozen
        end
      end
    end

    describe '.frozen_dup' do
      context 'when given a numeric' do
        it 'returns the original input' do
          input = 10.0

          result = described_class.frozen_dup(input)

          expect(input).to be_frozen

          expect(result).to be(input)
          expect(result).to be_frozen
        end
      end
    end
  end
end
