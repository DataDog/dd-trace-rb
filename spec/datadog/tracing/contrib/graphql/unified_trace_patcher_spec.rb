require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/graphql/test_schema_examples'
require 'datadog/tracing/contrib/graphql/unified_trace_patcher'

require 'datadog'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::UnifiedTracePatcher,
  skip: Gem::Version.new(::GraphQL::VERSION) < Gem::Version.new('2.0.19') do
    describe '#patch!' do
      context 'with empty schema configuration' do
        it_behaves_like 'graphql instrumentation with unified naming convention trace' do
          before do
            described_class.patch!([], {})
          end
        end
      end

      context 'with specified schemas configuration' do
        it_behaves_like 'graphql instrumentation with unified naming convention trace' do
          before do
            described_class.patch!([TestGraphQLSchema], {})
          end
        end
      end
    end

    # Not specific to unified trace patcher,
    # But this should work the same way without the need to require the tracer in the schema.
    describe '#trace_with' do
      context 'with schema using trace_with' do
        it_behaves_like 'graphql instrumentation with unified naming convention trace' do
          before do
            # Monkey patch the schema to use the unified tracer
            # As we're not adding a new method, we cannot use allow(...).to receive(...)
            # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
            class TestGraphQLSchema
              trace_with Datadog::Tracing::Contrib::GraphQL::UnifiedTrace
            end
            # rubocop:enable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
          end
        end
      end
    end
  end
