require 'datadog/tracing/contrib/graphql/configuration/settings'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::Configuration::Settings do
  describe 'schemas' do
    context 'when given an empty array' do
      it do
        expect(Datadog.logger).to receive(:warn).with(/no GraphQL schema being instrumentated/)

        settings = described_class.new(schemas: [])

        expect(settings.schemas).to eq([])
      end
    end
  end
end
