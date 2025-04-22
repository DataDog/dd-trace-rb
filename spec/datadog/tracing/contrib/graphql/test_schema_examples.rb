require 'graphql'
require 'ostruct'

require_relative 'test_helpers'

def load_test_schema(prefix: '')
  # rubocop:disable Security/Eval
  # rubocop:disable Style/DocumentDynamicEvalDefinition
  eval <<-RUBY, binding, __FILE__, __LINE__ + 1
    class #{prefix}TestUserType < ::GraphQL::Schema::Object
      field :id, ::GraphQL::Types::ID, null: false
      field :name, ::GraphQL::Types::String, null: true
      field :created_at, ::GraphQL::Types::String, null: false
      field :updated_at, ::GraphQL::Types::String, null: false
    end

    class #{prefix}TestGraphQLQuery < ::GraphQL::Schema::Object
      field :user, #{prefix}TestUserType, null: false, description: 'Find user' do
        argument :id, ::GraphQL::Types::ID, required: true
      end

      def user(id:)
        OpenStruct.new(id: id, name: 'Bits')
      end

      field :graphql_error, ::GraphQL::Types::Int, description: 'Raises error'

      def graphql_error
        raise 'GraphQL error'
      end
    end

    class #{prefix}TestGraphQLSchema < ::GraphQL::Schema
      query(#{prefix}TestGraphQLQuery)

      rescue_from(RuntimeError) do |err, obj, args, ctx, field|
        raise GraphQL::ExecutionError.new(err.message, extensions: {
          'int': 1,
          'bool': true,
          'str': '1',
          'array-1-2': [1, '2'],
          'hash-a-b': {a: 'b'},
          'object': ::Object.new,
          'extra-int': 2, # This should not be included
        })
      end
    end
  RUBY
  # rubocop:enable Style/DocumentDynamicEvalDefinition
  # rubocop:enable Security/Eval
end

def unload_test_schema(prefix: '')
  Object.send(:remove_const, :"#{prefix}TestUserType")
  Object.send(:remove_const, :"#{prefix}TestGraphQLQuery")
  Object.send(:remove_const, :"#{prefix}TestGraphQLSchema")
end

RSpec.shared_examples 'graphql default instrumentation' do
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

RSpec.shared_examples 'graphql instrumentation with unified naming convention trace' do |prefix: ''|
  let(:schema) { Object.const_get("#{prefix}TestGraphQLSchema") }
  let(:service) { defined?(super) ? super() : tracer.default_service }

  describe 'query trace' do
    subject(:result) { schema.execute(query: 'query Users($var: ID!){ user(id: $var) { name } }', variables: { var: 1 }) }

    matrix = [
      ['graphql.analyze', 'query Users($var: ID!){ user(id: $var) { name } }'],
      ['graphql.analyze_multiplex', 'Users'],
      ['graphql.authorized', "#{prefix}TestGraphQLQuery.authorized"],
      ['graphql.authorized', "#{prefix}TestUser.authorized"],
      ['graphql.execute', 'Users'],
      ['graphql.execute_lazy', 'Users'],
      ['graphql.execute_multiplex', 'Users'],
      if Gem::Version.new(GraphQL::VERSION) < Gem::Version.new('2.2')
        ['graphql.lex', 'query Users($var: ID!){ user(id: $var) { name } }']
      end,
      ['graphql.parse', 'query Users($var: ID!){ user(id: $var) { name } }'],
      ['graphql.resolve', "#{prefix}TestGraphQLQuery.user"],
      ['graphql.resolve', "#{prefix}TestUser.name"],
      # New Ruby-based parser doesn't emit a "lex" event. (graphql/c_parser still does.)
      ['graphql.validate', 'Users']
    ].compact

    # graphql.source for execute_multiplex is not required in the span attributes specification
    spans_with_source = ['graphql.parse', 'graphql.validate', 'graphql.execute']

    matrix.each_with_index do |(name, resource), index|
      it "creates #{name} span with #{resource} resource" do
        expect(result.to_h['errors']).to be nil
        expect(result.to_h['data']).to eq({ 'user' => { 'name' => 'Bits' } })

        expect(spans).to have(matrix.length).items
        span = spans[index]

        expect(span.name).to eq(name)
        expect(span.resource).to eq(resource)
        expect(span.service).to eq(service)
        expect(span.type).to eq('graphql')

        if spans_with_source.include?(name)
          expect(span.get_tag('graphql.source')).to eq('query Users($var: ID!){ user(id: $var) { name } }')
        end

        if name == 'graphql.execute'
          expect(span.get_tag('graphql.operation.type')).to eq('query')
          expect(span.get_tag('graphql.operation.name')).to eq('Users')
          # graphql.variables.* in graphql.execute span are the ones defined outside the query
          # (variables part in JSON for example)
          expect(span.get_tag('graphql.variables.var')).to eq(1)
        end

        if name == 'graphql.resolve' && resource == 'TestGraphQLQuery.user'
          # During graphql.resolve, it converts it to string (as it builds an SQL query for example)
          expect(span.get_tag('graphql.variables.id')).to eq('1')
        end
      end
    end
  end

  describe 'query with GraphQL errors' do
    subject(:result) { schema.execute(query: 'query Error{ err1: graphqlError err2: graphqlError }') }

    let(:graphql_execute) { spans.find { |s| s.name == 'graphql.execute' } }

    it 'creates query span for error' do
      expect(result.to_h['errors'][0]['message']).to eq('GraphQL error')
      expect(result.to_h['data']).to eq('err1' => nil, 'err2' => nil)

      expect(graphql_execute.resource).to eq('Error')
      expect(graphql_execute.service).to eq(service)
      expect(graphql_execute.type).to eq('graphql')

      expect(graphql_execute.get_tag('graphql.source')).to eq('query Error{ err1: graphqlError err2: graphqlError }')

      expect(graphql_execute.get_tag('graphql.operation.type')).to eq('query')
      expect(graphql_execute.get_tag('graphql.operation.name')).to eq('Error')

      expect(graphql_execute.events).to contain_exactly(
        a_span_event_with(
          name: 'dd.graphql.query.error',
          attributes: {
            'path' => ['err1'],
            'locations' => ['1:14'],
            'message' => 'GraphQL error',
            'type' => 'GraphQL::ExecutionError',
            'stacktrace' => include(__FILE__),
          }
        ),
        a_span_event_with(
          name: 'dd.graphql.query.error',
          attributes: {
            'path' => ['err2'],
            'locations' => ['1:33'],
            'message' => 'GraphQL error',
            'type' => 'GraphQL::ExecutionError',
            'stacktrace' => include(__FILE__),
          }
        )
      )
    end

    context 'with error extension capture enabled' do
      around do |ex|
        ClimateControl.modify('DD_TRACE_GRAPHQL_ERROR_EXTENSIONS' => 'int,str,bool,array-1-2,hash-a-b,object') { ex.run }
      end

      it 'creates query span for error with extensions' do
        expect(result.to_h['errors'][0]['message']).to eq('GraphQL error')

        expect(graphql_execute.events[0]).to match(
          a_span_event_with(
            name: 'dd.graphql.query.error',
            attributes: {
              'path' => ['err1'],
              'locations' => ['1:14'],
              'message' => 'GraphQL error',
              'type' => 'GraphQL::ExecutionError',
              'stacktrace' => include(__FILE__),
              'extensions.int' => 1,
              'extensions.bool' => true,
              'extensions.str' => '1',
              'extensions.array-1-2' => '[1, "2"]',
              'extensions.hash-a-b' => { a: 'b' }.to_s, # Hash#to_s changes per Ruby version: 3.3: '{:a=>1}', 3.4: '{a: 1}'
              'extensions.object' => start_with('#<Object:'),
            }
          )
        )

        expect(graphql_execute.events[0].attributes).to_not include('extensions.extra-int')
      end
    end
  end
end
