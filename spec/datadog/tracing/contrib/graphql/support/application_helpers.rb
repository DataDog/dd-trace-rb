require 'graphql'
require 'json'

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
