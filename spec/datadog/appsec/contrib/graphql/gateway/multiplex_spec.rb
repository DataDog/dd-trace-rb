# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/graphql/graphql_helper'

require 'datadog/appsec/contrib/graphql/gateway/multiplex'

RSpec.describe Datadog::AppSec::Contrib::GraphQL::Gateway::Multiplex do
  include_context 'with GraphQL multiplex'

  let(:gateway) do
    described_class.new(multiplex)
  end

  describe '#arguments' do
    it 'returns the arguments of all queries' do
      expect(gateway.arguments).to eq({ 'test' => [{ 'id' => 1 }, { 'id' => 10 }], 'query3' => [{ 'name' => 'Caniche' }] })
    end
  end

  describe '#queries' do
    it 'returns the queries that make the multiplex' do
      result = [
        'query test{ user(id: 1) { name } }',
        'query test{ user(id: 10) { name } }',
        'query { userByName(name: "Caniche") { id } }'
      ]
      expect(gateway.queries.map(&:query_string)).to match_array(result)
    end
  end
end
