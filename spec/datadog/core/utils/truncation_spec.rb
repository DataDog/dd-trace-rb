# frozen_string_literal: true

require 'datadog/core/utils/truncation'

RSpec.describe Datadog::Core::Utils::Truncation do
  describe '.truncate_in_middle' do
    subject(:truncated) do
      described_class.truncate_in_middle(string, 5, 5)
    end

    context 'short string' do
      let(:string) { 'hello' }

      it 'returns the original string' do
        expect(truncated).to eq(string)
      end
    end

    context 'long string' do
      let(:string) { 'hello' * 3 }

      it 'returns the truncated string' do
        expect(truncated).to eq('hello...hello')
      end
    end

    context 'string of maximum untruncated length' do
      let(:string) { 'helloXXXhello' }

      it 'returns the original string' do
        expect(truncated).to eq('helloXXXhello')
      end
    end

    context 'string of maximum untruncated length + 1 character' do
      let(:string) { 'helloXXXYhello' }

      it 'returns the truncated string' do
        expect(truncated).to eq('hello...hello')
      end
    end
  end
end
