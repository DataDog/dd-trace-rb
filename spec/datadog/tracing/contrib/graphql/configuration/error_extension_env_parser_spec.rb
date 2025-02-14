require 'datadog/tracing/contrib/graphql/configuration/error_extension_env_parser'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::Configuration::ErrorExtensionEnvParser do
  describe '.call' do
    subject(:call) { described_class.call(value) }

    context 'when value is an empty string' do
      let(:value) { '' }
      it 'returns an empty array' do
        is_expected.to eq([])
      end
    end

    context 'when value contains multiple commas' do
      let(:value) { 'foo,bar,baz' }
      it 'returns an array with split values' do
        is_expected.to eq(['foo', 'bar', 'baz'])
      end
    end

    context 'when value contains leading and trailing whitespace' do
      let(:value) { ' foo  , bar   , baz ' }
      it 'removes whitespace around values' do
        is_expected.to eq(['foo', 'bar', 'baz'])
      end
    end

    context 'when value contains empty elements' do
      let(:value) { ',foo,,bar,,baz,' }
      it 'removes the empty elements' do
        is_expected.to eq(['foo', 'bar', 'baz'])
      end
    end

    context 'when value contains repeated elements' do
      let(:value) { 'foo,foo' }
      it 'remove repeated elements' do
        is_expected.to eq(['foo'])
      end
    end
  end
end
