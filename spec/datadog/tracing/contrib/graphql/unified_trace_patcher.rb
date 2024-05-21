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
        it_behaves_like 'graphql default instrumentation with unified naming convention trace' do
          before do
            described_class.patch!([TestGraphQLSchema], {})
          end
        end
      end
    end
  end
