# encoding: utf-8

require 'spec_helper'
require 'ddtrace/quantization/hash'

RSpec.describe Datadog::Quantization::Hash do
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
  end
end
