require 'spec_helper'
require 'datadog/tracing/contrib/utils/quantization/hash'

RSpec.describe Datadog::Tracing::Contrib::Utils::Quantization::Hash do
  describe '#format' do
    subject(:result) { described_class.format(hash, options) }

    let(:options) { {} }

    context 'given a Hash' do
      let(:hash) { { one: 'foo', two: 'bar', three: 'baz' } }

      context 'default behavior' do
        it { is_expected.to eq(one: '?', two: '?', three: '?') }
      end

      context 'with show: value' do
        let(:options) { { show: [:two] } }

        it { is_expected.to eq(one: '?', two: 'bar', three: '?') }
      end

      context 'with show: :all' do
        let(:options) { { show: :all } }

        it { is_expected.to eq(hash) }
      end

      context 'with exclude: value' do
        let(:options) { { exclude: [:three] } }

        it { is_expected.to eq(one: '?', two: '?') }
      end

      context 'with exclude: value with indifferent key matching' do
        let(:options) { { exclude: ['three'] } }

        it { is_expected.to eq(one: '?', two: '?') }
      end

      context 'with exclude: :all' do
        let(:options) { { exclude: :all } }

        it { is_expected.to eq({}) }
      end
    end

    context 'given an Array' do
      let(:hash) { %w[foo bar baz] }

      context 'default behavior' do
        it { is_expected.to eq(['?']) }
      end

      context 'with show: value' do
        let(:options) { { show: [:two] } }

        it { is_expected.to eq(['?']) }
      end

      context 'with show: :all' do
        let(:options) { { show: :all } }

        it { is_expected.to eq(hash) }
      end

      context 'with exclude: value' do
        let(:options) { { exclude: [:three] } }

        it { is_expected.to eq(['?']) }
      end

      context 'with exclude: :all' do
        let(:options) { { exclude: :all } }

        it { is_expected.to eq(['?']) }
      end
    end

    context 'given a Array with nested arrays' do
      let(:hash) { [%w[foo bar baz], %w[foo], %w[bar], %w[baz]] }

      it { is_expected.to eq([['?'], '?']) }
    end

    context 'given a Array with nested hashes' do
      let(:hash) { [{ foo: { bar: 1 } }, { foo: { bar: 2 } }] }

      it { is_expected.to eq([{ foo: { bar: '?' } }, '?']) }
    end
  end
end
