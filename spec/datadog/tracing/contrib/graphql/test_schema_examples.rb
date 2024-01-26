LogHelpers.without_warnings do
  require 'graphql'
end

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
    OpenStruct.new(id: id, name: 'Bits')
  end
end

class TestGraphQLSchema < ::GraphQL::Schema
  query(TestGraphQLQuery)
end

RSpec.shared_examples 'graphql instrumentation' do
  describe 'query trace' do
    subject(:result) { TestGraphQLSchema.execute('{ user(id: 1) { name } }') }

    matrix = [
      ['TestGraphQLQuery.authorized', 'authorized'],
      ['TestGraphQLQuery.user', 'execute_field'],
      ['TestUser.authorized', 'authorized'],
      ['analyze.graphql', 'analyze_multiplex'],
      ['analyze.graphql', 'analyze_query'],
      ['execute.graphql', 'execute_multiplex'],
      ['execute.graphql', 'execute_query'],
      ['execute.graphql', 'execute_query_lazy'],
      # New Ruby-based parser doesn't emit a "lex" event. (graphql/c_parser still does.)
      (['lex.graphql', 'lex'] if Gem::Version.new(GraphQL::VERSION) < Gem::Version.new('2.2')),
      ['parse.graphql', 'parse'],
      ['validate.graphql', 'validate']
    ].compact

    matrix.each_with_index do |(name, operation), index|
      it "creates #{name} span with #{operation} operation" do
        expect(result.to_h['errors']).to be nil
        expect(spans).to have(matrix.length).items

        span = spans[index]

        expect(span.name).to eq(name)
        expect(span.resource).to eq(name)
        expect(span.service).to eq(tracer.default_service)
        expect(span.type).to eq('custom')
        expect(span.get_tag('component')).to eq('graphql')
        expect(span.get_tag('operation')).to eq(operation)
      end
    end
  end
end
