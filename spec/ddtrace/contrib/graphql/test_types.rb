# typed: ignore
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

class LazyFindPerson
  def initialize(query_ctx, person_id)
    @person_id = person_id
    # Initialize the loading state for this query,
    # or get the previously-initiated state
    @lazy_state = query_ctx[:lazy_find_person] ||= {
      pending_ids: Set.new,
      loaded_ids: {},
    }
    # Register this ID to be loaded later:
    @lazy_state[:pending_ids] << person_id
  end

  # Return the loaded record, hitting the database if needed
  def sync
    # Check if the record was already loaded:
    loaded_record = @lazy_state[:loaded_ids][@person_id]
    if loaded_record
      # The pending IDs were already loaded,
      # so return the result of that previous load
      loaded_record
    else
      "expensive string"
      # The record hasn't been loaded yet, so
      # hit the database with all pending IDs
      # pending_ids = @lazy_state[:pending_ids].to_a
      # people = Person.where(id: pending_ids)
      # people.each { |person| @lazy_state[:loaded_ids][person.id] = person }
      # @lazy_state[:pending_ids].clear
      # # Now, get the matching person from the loaded result:
      # @lazy_state[:loaded_ids][@person_id]
    end
  end
end


RSpec.shared_context 'GraphQL class-based schema' do
  include_context 'GraphQL base schema types'

  let(:schema) do
    qt = query_type
    Class.new(::GraphQL::Schema) do
      query(qt)

      # use #custom resolver like
      # use BatchLoader::GraphQL
      #
      # lazy_resolve(BatchLoader::GraphQL, :sync) # i think this is the key


      lazy_resolve LazyFindPerson, :sync

      # TODO to investigate
      # use GraphQL::Analysis::AST
      # query_analyzer GraphQL::Ext::PiiQueryAnalyzer
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

      def name
        # with these active span in the context:
        # execute.graphql:execute.graphql(fer,↑0)
        # lex.graphql:lex.graphql(ib3r,↑fer)
        LazyFindPerson.new(context, object.id)
      end
    end)
  end
end

#  .define-style schema is deprecated and will be removed in
# `graphql` 2.0: https://graphql-ruby.org/schema/class_based_api.html
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
        argument :id, !GraphQL::Types::ID.graphql_definition
        description 'Find an object by ID'
        resolve ->(_obj, args, _ctx) { oc.new(args['id']) }
      end
    end
  end

  let(:object_type) do
    otn = object_type_name

    ::GraphQL::ObjectType.define do
      name otn
      field :id, !GraphQL::Types::ID.graphql_definition
      field :name, GraphQL::Types::String.graphql_definition
      field :created_at, !GraphQL::Types::String.graphql_definition
      field :updated_at, !GraphQL::Types::String.graphql_definition
    end
  end
end
