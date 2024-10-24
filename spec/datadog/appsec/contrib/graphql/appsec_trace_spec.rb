# frozen_string_literal: true

require 'datadog/tracing/contrib/graphql/support/application'

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/graphql/appsec_trace'

RSpec.describe Datadog::AppSec::Contrib::GraphQL::AppSecTrace do
  include_context 'with GraphQL schema'

  it 'returns the correct result when given a valid query' do
    bits = schema.execute('query test{ user(id: 1) { name } }')
    expect(bits.to_h).to eq({ 'data' => { 'user' => { 'name' => 'Bits' } } })

    caniche = schema.execute('query test{ user(id: 10) { name } }')
    expect(caniche.to_h).to eq({ 'data' => { 'user' => { 'name' => 'Caniche' } } })

    bits_by_name = schema.execute('query test{ userByName(name: "Bits") { id } }')
    expect(bits_by_name.to_h).to eq({ 'data' => { 'userByName' => { 'id' => '1' } } })

    caniche_by_name = schema.execute('query test{ userByName(name: "Caniche") { id } }')
    expect(caniche_by_name.to_h).to eq({ 'data' => { 'userByName' => { 'id' => '10' } } })
  end

  it 'returns an error when given an invalid query' do
    result = schema.execute('query test{ error(id: 10) { name } }')
    expect(result.to_h['data']).to be_nil
    expect(result.to_h['errors']).to eq(
      [
        {
          'message' => "Field 'error' doesn't exist on type 'Query'",
          'locations' => [{ 'line' => 1, 'column' => 13 }],
          'path' => ['query test', 'error'],
          'extensions' => { 'code' => 'undefinedField', 'typeName' => 'Query', 'fieldName' => 'error' }
        }
      ]
    )
  end

  include_context 'with GraphQL multiplex'
  it 'returns the correct result when given an valid multiplex' do
    result =
      if Gem::Version.new(::GraphQL::VERSION) < Gem::Version.new('2.0.0')
        schema.multiplex(
          queries.map do |query|
            {
              query: query.query_string,
              operation_name: query.operation_name,
              variables: query.variables
            }
          end
        )
      else
        schema.multiplex(queries)
      end

    expect(result.map(&:to_h)).to eq(
      [
        { 'data' => { 'user' => { 'name' => 'Bits' } } },
        { 'data' => { 'user' => { 'name' => 'Caniche' } } },
        { 'data' => { 'userByName' => { 'id' => '10' } } }
      ]
    )
  end

  it 'returns a partially correct result when given a multiplex with an invalid query' do
    queries << ::GraphQL::Query.new(schema, 'query test{ error(id: 10) { name } }')
    result =
      if Gem::Version.new(::GraphQL::VERSION) < Gem::Version.new('2.0.0')
        schema.multiplex(
          queries.map do |query|
            {
              query: query.query_string,
              operation_name: query.operation_name,
              variables: query.variables
            }
          end
        )
      else
        schema.multiplex(queries)
      end

    expect(result.map(&:to_h)).to eq(
      [
        { 'data' => { 'user' => { 'name' => 'Bits' } } },
        { 'data' => { 'user' => { 'name' => 'Caniche' } } },
        { 'data' => { 'userByName' => { 'id' => '10' } } },
        {
          'errors' =>
          [
            {
              'message' => "Field 'error' doesn't exist on type 'Query'",
              'locations' => [{ 'line' => 1, 'column' => 13 }],
              'path' => ['query test', 'error'],
              'extensions' => { 'code' => 'undefinedField', 'typeName' => 'Query', 'fieldName' => 'error' }
            }
          ]
        }
      ]
    )
  end
end
