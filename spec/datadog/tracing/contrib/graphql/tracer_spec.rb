require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/graphql/test_types'

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

  let(:root_span) { spans.find { |s| s.parent_id == 0 } }

  RSpec.shared_examples 'Schema patcher' do
    before do
      remove_patch!(:graphql)
      Datadog.configure do |c|
        c.tracing.instrument :graphql, schemas: [schema]
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
      let(:supports_component_operation_tag?) { Gem::Version.new(GraphQL::VERSION) > Gem::Version.new('2.0.6') }

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

        valid_operations = %w[
          analyze_multiplex
          analyze_query
          execute_field
          execute_multiplex
          execute_query
          execute_query_lazy
          lex
          parse
          validate
        ]

        # Legacy execution strategy
        # {GraphQL::Execution::Execute}
        # does not execute authorization code.
        # Can be removed when graphql < 2.0 support is dropped.
        if defined?(GraphQL::Execution::Execute) && schema.query_execution_strategy == GraphQL::Execution::Execute
          expect(spans).to have(9).items
        else
          valid_resource_names += [
            'Foo.authorized',
            'Query.authorized'
          ]

          valid_operations << 'authorized'

          expect(spans).to have(11).items
        end

        # Expect root span to be 'execute.graphql'
        expect(root_span.name).to eq('execute.graphql')
        expect(root_span.resource).to eq('execute.graphql')
        if supports_component_operation_tag?
          expect(root_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('graphql')
        end

        # TODO: Assert GraphQL root span sets analytics sample rate.
        #       Need to wait on pull request to be merged and GraphQL released.
        #       See https://github.com/rmosolgo/graphql-ruby/pull/2154

        # Expect each span to be properly named
        spans.each do |span|
          expect(span.service).to eq(tracer.default_service)
          expect(valid_resource_names).to include(span.resource)
          if supports_component_operation_tag?
            expect(valid_operations).to include(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          end
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
    before do
      if Gem::Version.new(GraphQL::VERSION) >= Gem::Version.new('2.0')
        skip('graphql >= 2.0 has deprecated this schema definition style')
      end
    end

    include_context 'GraphQL .define-style schema'
    # Legacy execution strategy (default before 1.12.0)
    let(:expected_execution_strategy) { GraphQL::Execution::Execute }

    it_behaves_like 'Schema patcher'
  end
end
