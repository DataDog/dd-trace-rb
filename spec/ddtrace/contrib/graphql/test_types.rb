LogHelpers.without_warnings do
  require 'graphql'
end

RSpec.shared_context 'GraphQL test schema' do
  let(:defined_schema) do
    qt = query_type

    ::GraphQL::Schema.define do
      query(qt)
    end
  end

  let(:derived_schema) do
    qt = query_type
    Class.new(::GraphQL::Schema) do
      query(qt)
    end
  end

  let(:query_type_name) { 'Query' }
  let(:query_type) do
    qtn = query_type_name
    ot = object_type
    oc = object_class

    ::GraphQL::ObjectType.define do
      name qtn
      field ot.name.downcase.to_sym do
        type ot
        argument :id, !types.ID
        description 'Find an object by ID'
        resolve ->(_obj, args, _ctx) { oc.new(args['id']) }
      end
    end
  end

  let(:object_type_name) { 'Foo' }
  let(:object_type) do
    otn = object_type_name

    ::GraphQL::ObjectType.define do
      name otn
      field :id, !types.ID
      field :name, types.String
      field :created_at, !types.String
      field :updated_at, !types.String
    end
  end

  let(:object_class) do
    Class.new do
      attr_accessor :id, :name

      def initialize(id, name = 'bar')
        @id = id
        @name = name
      end
    end
  end
end
