require 'graphql'
require 'json'

module TestGraphQL
  class Case < GraphQL::Schema::Directive
    argument :format, String
    locations FIELD

    TRANSFORMS = [
      "upcase",
      "downcase",
      # ??
    ]
    # Implement the Directive API
    def self.resolve(object, arguments, context)
      path = context.namespace(:interpreter)[:current_path]
      return_value = yield
      transform_name = arguments[:format]
      if TRANSFORMS.include?(transform_name) && return_value.respond_to?(transform_name)
        return_value = return_value.public_send(transform_name)
        response = context.namespace(:interpreter_runtime)[:runtime].final_result
        *keys, last = path
        keys.each do |key|
          if response && (response = response[key])
            next
          else
            break
          end
        end
        if response
          response[last] = return_value
        end
        nil
      end
    end
  end

  class UserType < ::GraphQL::Schema::Object
    field :id, ::GraphQL::Types::ID, null: false
    field :name, ::GraphQL::Types::String, null: true
    field :created_at, ::GraphQL::Types::String, null: false
    field :updated_at, ::GraphQL::Types::String, null: false
  end

  class Query < ::GraphQL::Schema::Object
    field :user, UserType, null: false, description: 'Find an user by ID' do
      argument :id, ::GraphQL::Types::ID, required: true
    end

    def user(id:)
      return OpenStruct.new(id: id, name: 'Caniche') if Integer(id) == 10

      OpenStruct.new(id: id, name: 'Bits')
    end

    field :userByName, UserType, null: false, description: 'Find an user by name' do
      argument :name, ::GraphQL::Types::String, required: true
    end

    # rubocop:disable Naming/MethodName
    def userByName(name:)
      return OpenStruct.new(id: 10, name: name) if name == 'Caniche'

      OpenStruct.new(id: 1, name: name)
    end

    field :mutationUserByName, UserType, null: false, description: 'Find an user by name' do
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

  class MutationType < ::GraphQL::Schema::Object
    class Mutation < ::GraphQL::Schema::Mutation
      argument :name, ::GraphQL::Types::String, required: true

      field :user, UserType
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

    field :create_user, mutation: Mutation
  end

  class Schema < ::GraphQL::Schema
    mutation(MutationType)
    query(Query)
    directive(Case)
  end
end