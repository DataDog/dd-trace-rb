require 'graphql'

class TestUserType < ::GraphQL::Schema::Object
  field :id, ::GraphQL::Types::ID, null: false
  field :name, ::GraphQL::Types::String, null: true
  field :created_at, ::GraphQL::Types::String, null: false
  field :updated_at, ::GraphQL::Types::String, null: false
end

class TestGraphQLQuery < ::GraphQL::Schema::Object
  field :user, TestUserType, null: false, description: 'Find an user by ID' do
    argument :id, ::GraphQL::Types::ID, required: true
  end

  def user(id:)
    return OpenStruct.new(id: id, name: 'Caniche') if Integer(id) == 10

    OpenStruct.new(id: id, name: 'Bits')
  end

  field :userByName, TestUserType, null: false, description: 'Find an user by name' do
    argument :name, ::GraphQL::Types::String, required: true
  end

  # rubocop:disable Naming/MethodName
  def userByName(name:)
    return OpenStruct.new(id: 10, name: name) if name == 'Caniche'

    OpenStruct.new(id: 1, name: name)
  end
  # rubocop:enable Naming/MethodName
end

class TestGraphQLSchema < ::GraphQL::Schema
  query(TestGraphQLQuery)
end

RSpec.shared_context 'with GraphQL schema' do
  let(:operation) { Datadog::AppSec::Reactive::Operation.new('test') }
  let(:schema) { TestGraphQLSchema }
end

RSpec.shared_context 'with GraphQL multiplex' do
  include_context 'with GraphQL schema'

  let(:first_query) { ::GraphQL::Query.new(schema, 'query test{ user(id: 1) { name } }') }
  let(:second_query) { ::GraphQL::Query.new(schema, 'query test{ user(id: 10) { name } }') }
  let(:third_query) { ::GraphQL::Query.new(schema, 'query { userByName(name: "Caniche") { id } }') }
  let(:queries) { [first_query, second_query, third_query] }
  let(:context) { { :dataloader => GraphQL::Dataloader.new(nonblocking: nil) } }
  let(:multiplex) do
    Datadog::AppSec::Contrib::GraphQL::Gateway::Multiplex.new(
      ::GraphQL::Execution::Multiplex.new(schema: schema, queries: queries, context: context, max_complexity: nil)
    )
  end
end
