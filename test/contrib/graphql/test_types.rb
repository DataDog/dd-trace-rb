module Datadog
  module Contrib
    module GraphQL
      class Foo
        attr_accessor :id, :name

        def initialize(id, name = 'bar')
          @id = id
          @name = name
        end
      end

      FooType = ::GraphQL::ObjectType.define do
        name 'Foo'
        field :id, !types.ID
        field :name, types.String
        field :created_at, !types.String
        field :updated_at, !types.String
      end

      QueryType = ::GraphQL::ObjectType.define do
        name 'Query'
        # Add root-level fields here.
        # They will be entry points for queries on your schema.

        field :foo do
          type FooType
          argument :id, !types.ID
          description 'Find a Foo by ID'
          resolve ->(_obj, args, _ctx) { Foo.new(args['id']) }
        end
      end
    end
  end
end
