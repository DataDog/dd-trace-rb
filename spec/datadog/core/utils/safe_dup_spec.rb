require 'datadog/core/utils/safe_dup'

RSpec.describe Datadog::Core::Utils::SafeDup do
  describe '.frozen_or_dup' do
    it do
      input = 'a_frozen_string'.freeze

      result = described_class.frozen_or_dup(input)

      expect(result).to eq(input)
      expect(result).to equal(input)
      expect(result).to be_frozen
    end

    it do
      input = 'a_string'

      result = described_class.frozen_or_dup(input)

      expect(result).to eq(input)
      expect(result).not_to equal(input)
      expect(result).not_to be_frozen
    end
  end

  describe '.frozen_dup' do
    it do
      input = 'a_frozen_string'.freeze

      result = described_class.frozen_dup(input)

      expect(result).to eq(input)
      expect(result).to equal(input)
      expect(result).to be_frozen
    end

    it do
      input = 'a_string'

      result = described_class.frozen_dup(input)

      expect(result).to eq(input)
      expect(result).not_to equal(input)
      expect(result).to be_frozen
    end
  end
end
