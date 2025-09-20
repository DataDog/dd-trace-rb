require 'graphql'
require 'ostruct'

require_relative 'test_helpers'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/graphql/unified_trace_patcher'
require 'datadog'

def load_test_schema(prefix: '')
  # rubocop:disable Security/Eval
  # rubocop:disable Style/DocumentDynamicEvalDefinition
  eval <<-RUBY, binding, __FILE__, __LINE__ + 1
    class #{prefix}TestUserFilterInput < ::GraphQL::Schema::InputObject
      argument :name, ::GraphQL::Types::String, required: false
      argument :active, ::GraphQL::Types::Boolean, required: false
      argument :min_age, ::GraphQL::Types::Int, required: false
    end

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

      field :user_with_org, #{prefix}TestUserType, null: false, description: 'Find user with org' do
        argument :id, ::GraphQL::Types::ID, required: true
        argument :org, ::GraphQL::Types::ID, required: true
      end

      def user_with_org(id:, org:)
        OpenStruct.new(id: id, name: 'Bits', org: org)
      end

      field :user_with_filter, #{prefix}TestUserType, null: false, description: 'Find user with filter' do
        argument :id, ::GraphQL::Types::ID, required: true
        argument :active, ::GraphQL::Types::Boolean, required: true
      end

      def user_with_filter(id:, active:)
        OpenStruct.new(id: id, name: 'Bits', active: active)
      end

      field :user_with_details, #{prefix}TestUserType, null: false, description: 'Find user with details' do
        argument :id, ::GraphQL::Types::ID, required: true
        argument :name, ::GraphQL::Types::String, required: false
        argument :count, ::GraphQL::Types::Int, required: false
      end

      def user_with_details(id:, name: nil, count: nil)
        OpenStruct.new(id: id, name: name || 'Bits', count: count)
      end

      field :user_with_input_filter, #{prefix}TestUserType, null: false, description: 'Find user with input filter' do
        argument :id, ::GraphQL::Types::ID, required: true
        argument :filter, #{prefix}TestUserFilterInput, required: true
      end

      def user_with_input_filter(id:, filter:)
        OpenStruct.new(id: id, name: 'Bits', filter: filter)
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
  Object.send(:remove_const, :"#{prefix}TestUserFilterInput")
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
    subject(:result) { schema.execute(query: 'query Users($var: ID!){ user(id: $var) { name } }', variables: {var: 1}) }

    matrix = [
      ['graphql.analyze', 'query Users($var: ID!){ user(id: $var) { name } }'],
      ['graphql.analyze_multiplex', 'Users'],
      ['graphql.authorized', "#{prefix}TestGraphQLQuery.authorized"],
      ['graphql.authorized', "#{prefix}TestUser.authorized"],
      ['graphql.execute', 'query Users'],
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
        expect(result.to_h['data']).to eq({'user' => {'name' => 'Bits'}})

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
          # Variables are now only captured when explicitly configured
          # By default, no variables are captured
          expect(span.get_tag('graphql.variables.var')).to be_nil

          expect(span.get_tag('span.kind')).to eq('server')
        end

        if name == 'graphql.resolve' && resource == 'TestGraphQLQuery.user'
          # Field arguments are still captured with legacy graphql.variables.* tags
          # This is different from operation variables which use graphql.operation.variable.* tags
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

      expect(graphql_execute.resource).to eq('query Error')
      expect(graphql_execute.service).to eq(service)
      expect(graphql_execute.type).to eq('graphql')

      expect(graphql_execute.get_tag('graphql.source')).to eq('query Error{ err1: graphqlError err2: graphqlError }')

      expect(graphql_execute.get_tag('graphql.operation.type')).to eq('query')
      expect(graphql_execute.get_tag('graphql.operation.name')).to eq('Error')

      expect(graphql_execute.get_tag('span.kind')).to eq('server')

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
              'extensions.hash-a-b' => {a: 'b'}.to_s, # Hash#to_s changes per Ruby version: 3.3: '{:a=>1}', 3.4: '{a: 1}'
              'extensions.object' => start_with('#<Object:'),
            }
          )
        )

        expect(graphql_execute.events[0].attributes).to_not include('extensions.extra-int')
      end
    end

    context 'with error tracking enabled' do
      around do |ex|
        ClimateControl.modify(
          'DD_TRACE_GRAPHQL_ERROR_TRACKING' => 'true',
          'DD_TRACE_GRAPHQL_ERROR_EXTENSIONS' => 'int'
        ) { ex.run }
      end

      it 'creates exception span events with OpenTelemetry semantics and extensions' do
        expect(result.to_h['errors'][0]['message']).to eq('GraphQL error')

        expect(graphql_execute.events[0]).to match(
          a_span_event_with(
            name: 'exception',
            attributes: {
              'exception.message' => 'GraphQL error',
              'exception.type' => 'GraphQL::ExecutionError',
              'exception.stacktrace' => include(__FILE__),
              'graphql.error.path' => ['err1'],
              'graphql.error.locations' => ['1:14'],
              'graphql.error.extensions.int' => 1,
            }
          )
        )
      end
    end
  end

  describe 'operation variable capture' do
    let(:graphql_execute) { spans.find { |s| s.name == 'graphql.execute' } }

    context 'with no configuration (default behavior)' do
      it 'does not capture any variables' do
        schema.execute(query: 'query Users($var: ID!){ user(id: $var) { name } }', variables: {var: 1})

        expect(graphql_execute.get_tag('graphql.operation.variable.var')).to be_nil
      end
    end

    context 'with DD_TRACE_GRAPHQL_CAPTURE_VARIABLES configured' do
      around do |ex|
        ClimateControl.modify('DD_TRACE_GRAPHQL_CAPTURE_VARIABLES' => 'Users:var,GetUser:id') do
          # Reset configuration to pick up environment variable
          Datadog.configuration.tracing[:graphql].reset!
          ex.run
        end
      end

      it 'captures configured variables' do
        schema.execute(query: 'query Users($var: ID!){ user(id: $var) { name } }', variables: {var: 1})

        expect(graphql_execute.get_tag('graphql.operation.variable.var')).to eq(1)
      end

      it 'does not capture unconfigured variables' do
        schema.execute(
          query: 'query GetUser($id: ID!, $org: ID!){ userWithOrg(id: $id, org: $org) { name } }',
          variables: {id: 1, org: 2}
        )

        expect(graphql_execute.get_tag('graphql.operation.variable.id')).to eq(1)
        expect(graphql_execute.get_tag('graphql.operation.variable.org')).to be_nil
      end

      it 'does not capture variables for different operations' do
        schema.execute(query: 'query DifferentOp($var: ID!){ user(id: $var) { name } }', variables: {var: 1})

        expect(graphql_execute.get_tag('graphql.operation.variable.var')).to be_nil
      end
    end

    context 'with DD_TRACE_GRAPHQL_CAPTURE_VARIABLES_EXCEPT configured' do
      around do |ex|
        ClimateControl.modify(
          'DD_TRACE_GRAPHQL_CAPTURE_VARIABLES' => 'Users:var,Users:org',
          'DD_TRACE_GRAPHQL_CAPTURE_VARIABLES_EXCEPT' => 'Users:org'
        ) do
          Datadog.configuration.tracing[:graphql].reset!
          ex.run
        end
      end

      it 'captures variables except those in the except list' do
        schema.execute(
          query: 'query Users($var: ID!, $org: ID!){ userWithOrg(id: $var, org: $org) { name } }',
          variables: {var: 1, org: 2}
        )

        expect(graphql_execute.get_tag('graphql.operation.variable.var')).to eq(1)
        expect(graphql_execute.get_tag('graphql.operation.variable.org')).to be_nil
      end
    end

    context 'with only DD_TRACE_GRAPHQL_CAPTURE_VARIABLES_EXCEPT configured' do
      around do |ex|
        ClimateControl.modify('DD_TRACE_GRAPHQL_CAPTURE_VARIABLES_EXCEPT' => 'Users:org') do
          Datadog.configuration.tracing[:graphql].reset!
          ex.run
        end
      end

      it 'captures all variables except those in the except list' do
        schema.execute(
          query: 'query Users($var: ID!, $org: ID!){ userWithOrg(id: $var, org: $org) { name } }',
          variables: {var: 1, org: 2}
        )

        expect(graphql_execute.get_tag('graphql.operation.variable.var')).to eq(1)
        expect(graphql_execute.get_tag('graphql.operation.variable.org')).to be_nil
      end
    end

    context 'with anonymous operations' do
      around do |ex|
        ClimateControl.modify('DD_TRACE_GRAPHQL_CAPTURE_VARIABLES_EXCEPT' => '') do
          Datadog.configuration.tracing[:graphql].reset!
          ex.run
        end
      end

      it 'never captures variables for anonymous operations' do
        schema.execute(query: '{ user(id: "1") { name } }')

        expect(graphql_execute.resource).to eq('anonymous')
      end
    end

    context 'variable serialization' do
      around do |ex|
        ClimateControl.modify('DD_TRACE_GRAPHQL_CAPTURE_VARIABLES' => 'TestIntQuery:intVar,TestStringQuery:stringVar,TestBoolQuery:boolVar,TestIdQuery:idVar,TestInputQuery:inputVar') do
          Datadog.configuration.tracing[:graphql].reset!
          ex.run
        end
      end

      it 'serializes integer variables correctly' do
        schema.execute(
          query: 'query TestIntQuery($intVar: Int!){ userWithDetails(id: "1", count: $intVar) { name } }',
          variables: {intVar: 42}
        )

        expect(graphql_execute.get_tag('graphql.operation.variable.intVar')).to eq(42)
      end

      it 'serializes string variables correctly' do
        schema.execute(
          query: 'query TestStringQuery($stringVar: String!){ userWithDetails(id: "1", name: $stringVar) { name } }',
          variables: {stringVar: 'hello'}
        )

        expect(graphql_execute.get_tag('graphql.operation.variable.stringVar')).to eq('hello')
      end

      [
        {value: true, expected: 'true'},
        {value: false, expected: 'false'}
      ].each do |test_case|
        it "serializes #{test_case[:value]} boolean correctly" do
          schema.execute(
            query: 'query TestBoolQuery($boolVar: Boolean!){ userWithFilter(id: "1", active: $boolVar) { name } }',
            variables: {boolVar: test_case[:value]}
          )

          expect(graphql_execute.get_tag('graphql.operation.variable.boolVar')).to eq(test_case[:expected])
        end
      end

      it 'serializes ID variables correctly' do
        schema.execute(
          query: 'query TestIdQuery($idVar: ID!){ user(id: $idVar) { name } }',
          variables: {idVar: 'user123'}
        )

        expect(graphql_execute.get_tag('graphql.operation.variable.idVar')).to eq('user123')
      end

      it 'serializes custom input object variables correctly' do
        # Create a Ruby hash that represents a GraphQL input object
        # Use camelCase for GraphQL field names
        input_object = {name: 'John', active: true, minAge: 18}

        # For schemas without prefix, use the base type name
        input_type_name = if defined?(TraceWithTestUserFilterInput)
          'TraceWithTestUserFilterInput'
        else
          'TestUserFilterInput'
        end

        schema.execute(
          query: "query TestInputQuery($inputVar: #{input_type_name}!){ userWithInputFilter(id: \"1\", filter: $inputVar) { name } }",
          variables: {inputVar: input_object}
        )

        # Custom input objects should be serialized as strings using to_s
        # GraphQL converts hash keys from symbols to strings, so we expect the string key version
        expected_serialized = {'name' => 'John', 'active' => true, 'minAge' => 18}.to_s
        expect(graphql_execute.get_tag('graphql.operation.variable.inputVar')).to eq(expected_serialized)
      end
    end
  end
end
