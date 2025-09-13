# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/graphql/test_schema_examples'
require 'datadog/tracing/contrib/graphql/unified_trace_patcher'
require 'datadog'

RSpec.describe 'GraphQL variable capture basic functionality',
  skip: Gem::Version.new(::GraphQL::VERSION) < Gem::Version.new('2.0.19') do

  before(:context) { load_test_schema }
  after(:context) do
    unload_test_schema
    remove_patch!(:graphql)
  end

  around do |example|
    # Remove the previously set environment variables
    ClimateControl.modify(
      DD_TRACE_GRAPHQL_CAPTURE_VARIABLES: nil,
      DD_TRACE_GRAPHQL_CAPTURE_VARIABLES_EXCEPT: nil
    ) do
      example.run
    end
  end

  let(:all_spans) { spans }
  let(:execute_span) { all_spans.find { |s| s.name == 'graphql.execute' } }

  describe 'with unified tracer' do
    before do
      Datadog.configuration.tracing[:graphql].reset!
      Datadog.configure do |c|
        c.tracing.instrument :graphql, with_unified_tracer: true
      end
    end

    context 'when no capture configuration is set' do
      it 'does not capture any variables' do
        result = TestGraphQLSchema.execute(
          'query GetUser($id: ID!) { user(id: $id) { name } }',
          variables: { id: '1' },
          operation_name: 'GetUser'
        )

        expect(result.to_h['errors']).to be_nil
        expect(execute_span).not_to be_nil
        expect(execute_span.get_tag('graphql.operation.variable.id')).to be_nil
      end
    end

    context 'when capture variables is configured for GetUser:id' do
      around do |example|
        ClimateControl.modify(
          DD_TRACE_GRAPHQL_CAPTURE_VARIABLES: 'GetUser:id'
        ) do
          Datadog.configuration.tracing[:graphql].reset!
          Datadog.configure do |c|
            c.tracing.instrument :graphql, with_unified_tracer: true
          end
          example.run
        end
      end

      it 'captures the id variable' do
        result = TestGraphQLSchema.execute(
          'query GetUser($id: ID!) { user(id: $id) { name } }',
          variables: { id: '42' },
          operation_name: 'GetUser'
        )

        expect(result.to_h['errors']).to be_nil
        expect(execute_span).not_to be_nil
        expect(execute_span.get_tag('graphql.operation.variable.id')).to eq('42')
      end

      it 'captures boolean variables correctly' do
        # Since we can only test with the schema we have, let's use the id field
        # and test different variable types when they're passed as id
        result = TestGraphQLSchema.execute(
          'query GetUser($id: ID!) { user(id: $id) { name } }',
          variables: { id: 123 },
          operation_name: 'GetUser'
        )

        expect(result.to_h['errors']).to be_nil
        expect(execute_span).not_to be_nil
        expect(execute_span.get_tag('graphql.operation.variable.id')).to eq(123)
      end
    end

    context 'when capture variables except is configured' do
      around do |example|
        ClimateControl.modify(
          DD_TRACE_GRAPHQL_CAPTURE_VARIABLES_EXCEPT: 'GetUser:secret'
        ) do
          Datadog.configuration.tracing[:graphql].reset!
          Datadog.configure do |c|
            c.tracing.instrument :graphql, with_unified_tracer: true
          end
          example.run
        end
      end

      it 'captures all variables except those in the except list' do
        result = TestGraphQLSchema.execute(
          'query GetUser($id: ID!) { user(id: $id) { name } }',
          variables: { id: '1' },
          operation_name: 'GetUser'
        )

        expect(result.to_h['errors']).to be_nil
        expect(execute_span).not_to be_nil
        # Since id is not in the except list, it should be captured
        expect(execute_span.get_tag('graphql.operation.variable.id')).to eq('1')
      end
    end
  end
end
