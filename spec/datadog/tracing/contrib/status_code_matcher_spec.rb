require 'datadog/tracing/contrib/status_code_matcher'

RSpec.describe Datadog::Tracing::Contrib::StatusCodeMatcher do
  describe '#include?' do
    context 'when given a string to parse' do
      it do
        matcher = described_class.new('400')

        expect(matcher).to include 400
      end

      it do
        matcher = described_class.new('400,500')

        expect(matcher).to include 400
        expect(matcher).not_to include 499
        expect(matcher).to include 500
        expect(matcher).not_to include 599
      end

      it do
        matcher = described_class.new('400-500')

        expect(matcher).to include 400
        expect(matcher).to include 499
        expect(matcher).to include 500
        expect(matcher).not_to include 599
      end

      it do
        matcher = described_class.new('400-404,500')

        expect(matcher).to include 400
        expect(matcher).not_to include 499
        expect(matcher).to include 500
        expect(matcher).not_to include 599
      end
    end
  end
end
