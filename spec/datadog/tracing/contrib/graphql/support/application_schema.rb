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

  field :mutationUserByName, TestUserType, null: false, description: 'Find an user by name' do
    argument :name, ::GraphQL::Types::String, required: true
  end

  def mutationUserByName(name:)
    if Users.users[name].nil?
      ::GraphQL::ExecutionError.new('User not found')
    else
      OpenStruct.new(id: Users.users[name], name: name)
    end
  end
  # rubocop:enable Naming/MethodName
end

class Users
  class << self
    def users
      @users ||= {}
    end
  end
end

class TestGraphQLMutationType < ::GraphQL::Schema::Object
  class TestGraphQLMutation < ::GraphQL::Schema::Mutation
    argument :name, ::GraphQL::Types::String, required: true

    field :user, TestUserType
    field :errors, [String], null: false

    def resolve(name:)
      if Users.users.nil? || Users.users[name].nil?
        Users.users ||= {}
        item = OpenStruct.new(id: Users.users.size + 1, name: name)
        Users.users[name] = Users.users.size + 1
        { user: item, errors: [] }
      else
        ::GraphQL::ExecutionError.new('User already exists')
      end
    end
  end

  field :create_user, mutation: TestGraphQLMutation
end

class TestGraphQLSchema < ::GraphQL::Schema
  mutation(TestGraphQLMutationType)
  query(TestGraphQLQuery)
end
