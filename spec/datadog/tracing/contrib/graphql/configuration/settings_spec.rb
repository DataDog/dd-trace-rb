require 'datadog/tracing/contrib/graphql/configuration/settings'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::Configuration::Settings do
  describe 'schemas' do
    context 'when default' do
      it do
        settings = described_class.new

        expect(settings.schemas).to eq([])
      end
    end

    context 'when given an array' do
      it do
        schema = double

        settings = described_class.new(schemas: [schema])

        expect(settings.schemas).to eq([schema])
      end
    end

    context 'when given an empty array' do
      it do
        settings = described_class.new(schemas: [])

        expect(settings.schemas).to eq([])
      end
    end
  end
end
