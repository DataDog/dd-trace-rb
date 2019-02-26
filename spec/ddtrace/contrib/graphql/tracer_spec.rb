require 'spec_helper'
require 'ddtrace/contrib/graphql/test_types'

require 'ddtrace'
RSpec.describe 'GraphQL patcher' do
  include ConfigurationHelpers
  include_context 'GraphQL test schema'

  # GraphQL generates tons of warnings.
  # This suppresses those warnings.
  around(:each) do |example|
    without_warnings do
      example.run
    end
  end

  let(:tracer) { get_test_tracer }

  def pop_spans
    tracer.writer.spans(:keep)
  end

  let(:all_spans) { pop_spans }
  let(:root_span) { all_spans.find { |s| s.parent.nil? } }

  RSpec.shared_examples 'Schema patcher' do
    before(:each) do
      remove_patch!(:graphql)
      Datadog.configure do |c|
        c.use :graphql,
              service_name: 'graphql-test',
              tracer: tracer,
              schemas: [schema]
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

        # Expect nine spans
        expect(all_spans).to have(9).items

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

        # Expect root span to be 'execute.graphql'
        expect(root_span.name).to eq('execute.graphql')
        expect(root_span.resource).to eq('execute.graphql')

        # TODO: Assert GraphQL root span sets analytics sample rate.
        #       Need to wait on pull request to be merged and GraphQL released.
        #       See https://github.com/rmosolgo/graphql-ruby/pull/2154

        # Expect each span to be properly named
        all_spans.each do |span|
          expect(span.service).to eq('graphql-test')
          expect(valid_resource_names).to include(span.resource.to_s)
        end
      end
    end
  end

  context 'defined schema' do
    let(:schema) { defined_schema }
    it_should_behave_like 'Schema patcher'
  end

  context 'derived schema' do
    let(:schema) { derived_schema }
    it_should_behave_like 'Schema patcher'
  end
end
