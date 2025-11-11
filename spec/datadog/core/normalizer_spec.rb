require 'spec_helper'
require 'datadog/core/normalizer'

RSpec.describe Datadog::Core::Normalizer do
  describe '.normalize' do
    subject(:normalize) { described_class.normalize(input) }

    context 'keeps normal strings the same' do
        let(:input) {'regulartag'}
        let(:expected_output) {'regulartag'}
        it { is_expected.to eq(expected_output) }
    end

    context 'truncates long strings' do
        let(:input) {'a' * 201}
        let(:expected_output) {'a' * 200}
        it { is_expected.to eq(expected_output) }
    end

    context 'transforms special characters to underscores' do
        let(:input) {'a&**!'}
        let(:expected_output) {'a_'}
        it { is_expected.to eq(expected_output) }
    end

    context 'capital letters are lower cased' do
        let(:input) {'A'*10}
        let(:expected_output) {'a'*10}
        it { is_expected.to eq(expected_output) }
    end

    context 'removes whitespaces' do
        let(:input) {'  hi  '}
        let(:expected_output) {'hi'}
        it { is_expected.to eq(expected_output) }
    end

    context 'characters must start with a letter' do
        let(:input) {'1hi'}
        let(:expected_output) {'hi'}
        it { is_expected.to eq(expected_output) }
    end

    context 'if none of the characters are valid to start the value, the string is empty' do
        let(:input) {'111111111'}
        let(:expected_output) {''}
        it { is_expected.to eq(expected_output) }
    end
  end
end