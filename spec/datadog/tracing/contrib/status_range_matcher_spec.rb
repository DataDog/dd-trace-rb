require 'datadog/tracing/contrib/status_range_matcher'

RSpec.describe Datadog::Tracing::Contrib::StatusRangeMatcher do
  describe '#include?' do
    it do
      matcher = described_class.new(400)

      expect(matcher).to include 400
      expect(matcher).not_to include 401
      expect(matcher).not_to include 499
      expect(matcher).not_to include 500
      expect(matcher).not_to include 501
      expect(matcher).not_to include 599
    end

    it do
      matcher = described_class.new(400..500)

      expect(matcher).to include 400
      expect(matcher).to include 401
      expect(matcher).to include 499
      expect(matcher).to include 500
      expect(matcher).not_to include 501
      expect(matcher).not_to include 599
    end

    it do
      matcher = described_class.new([400..500])

      expect(matcher).to include 400
      expect(matcher).to include 401
      expect(matcher).to include 499
      expect(matcher).to include 500
      expect(matcher).not_to include 501
      expect(matcher).not_to include 599
    end

    it do
      matcher = described_class.new([400..401, 500])

      expect(matcher).to include 400
      expect(matcher).to include 401
      expect(matcher).not_to include 499
      expect(matcher).to include 500
      expect(matcher).not_to include 599
    end

    it do
      matcher = described_class.new([400..401, 500..600])

      expect(matcher).to include 400
      expect(matcher).to include 401
      expect(matcher).not_to include 499
      expect(matcher).to include 500
      expect(matcher).to include 599
    end
  end
end
