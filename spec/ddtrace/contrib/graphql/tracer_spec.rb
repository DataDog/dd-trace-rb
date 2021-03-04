require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/graphql/test_types'

require 'ddtrace'
RSpec.describe 'GraphQL patcher' do
  include ConfigurationHelpers

  # GraphQL generates tons of warnings.
  # This suppresses those warnings.
  around do |example|
    without_warnings do
      example.run
    end
  end

  let(:root_span) { spans.find { |s| s.parent.nil? } }

  RSpec.shared_examples 'Schema patcher' do
    before do
      remove_patch!(:graphql)
      Datadog.configure do |c|
        c.use :graphql,
              service_name: 'graphql-test',
              schemas: [schema]
      end
    end

    describe 'execution strategy' do
      it 'matches expected strategy' do
        expect(schema.query_execution_strategy).to eq(expected_execution_strategy)
      end
    end

    describe 'query trace' do
      subject(:result) { schema.execute(query, variables: {}, context: {}, operation_name: nil) }

      let(:query) { '{ foo(id: 1) { name } }' }
      let(:variables) { {} }
      let(:context) { {} }
      let(:operation_name) { nil }

      it do
        # Expect no errors
        expect(result.to_h['errors']).to be nil

        # List of valid resource names
        # (If this is too brittle, revist later.)
        valid_resource_names = [
          'Query.foo',
          'analyze.graphql',
          'execute.graphql',
          'lex.graphql',
          'parse.graphql',
          'validate.graphql'
        ]

        # Legacy execution strategy
        # {GraphQL::Execution::Execute}
        # does not execute authorization code.
        if schema.query_execution_strategy == GraphQL::Execution::Execute
          expect(spans).to have(9).items
        else
          valid_resource_names += [
            'Foo.authorized',
            'Query.authorized'
          ]

          expect(spans).to have(11).items
        end

        # Expect root span to be 'execute.graphql'
        expect(root_span.name).to eq('execute.graphql')
        expect(root_span.resource).to eq('execute.graphql')

        # TODO: Assert GraphQL root span sets analytics sample rate.
        #       Need to wait on pull request to be merged and GraphQL released.
        #       See https://github.com/rmosolgo/graphql-ruby/pull/2154

        # Expect each span to be properly named
        spans.each do |span|
          expect(span.service).to eq('graphql-test')
          expect(valid_resource_names).to include(span.resource)
        end
      end
    end
  end

  context 'class-based schema' do
    include_context 'GraphQL class-based schema'
    # Newer execution strategy (default since 1.12.0)
    let(:expected_execution_strategy) { GraphQL::Execution::Interpreter }

    it_behaves_like 'Schema patcher'
  end

  describe '.define-style schema' do
    include_context 'GraphQL .define-style schema'
    # Legacy execution strategy (default before 1.12.0)
    let(:expected_execution_strategy) { GraphQL::Execution::Execute }

    it_behaves_like 'Schema patcher'
  end
end
