LogHelpers.without_warnings do
  require 'graphql'
end

RSpec.shared_context 'GraphQL base schema types' do
  let(:query_type_name) { 'Query' }
  let(:object_type_name) { 'Foo' }
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

RSpec.shared_context 'GraphQL class-based schema' do
  include_context 'GraphQL base schema types'

  let(:schema) do
    qt = query_type
    Class.new(::GraphQL::Schema) do
      query(qt)
    end
  end

  let(:query_type) do
    qtn = query_type_name
    ot = object_type
    oc = object_class

    stub_const(qtn, Class.new(::GraphQL::Schema::Object) do
      field ot.graphql_name.downcase, ot, null: false, description: 'Find an object by ID' do
        argument :id, ::GraphQL::Types::ID, required: true
      end

      define_method ot.graphql_name.downcase do |args|
        oc.new(args[:id])
      end
    end)
  end

  let(:object_type) do
    otn = object_type_name

    stub_const(otn, Class.new(::GraphQL::Schema::Object) do
      field :id, ::GraphQL::Types::ID, null: false
      field :name, ::GraphQL::Types::String, null: true
      field :created_at, ::GraphQL::Types::String, null: false
      field :updated_at, ::GraphQL::Types::String, null: false
    end)
  end
end

RSpec.shared_context 'GraphQL .define-style schema' do
  include_context 'GraphQL base schema types'

  let(:schema) do
    qt = query_type

    ::GraphQL::Schema.define do
      query(qt)
    end
  end

  let(:query_type) do
    qtn = query_type_name
    ot = object_type
    oc = object_class

    ::GraphQL::ObjectType.define do
      name qtn
      field ot.name.downcase do
        type ot
        argument :id, !types.ID
        description 'Find an object by ID'
        resolve ->(_obj, args, _ctx) { oc.new(args['id']) }
      end
    end
  end

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
end
