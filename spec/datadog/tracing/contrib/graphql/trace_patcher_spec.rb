require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/graphql/test_schema_examples'
require 'datadog/tracing/contrib/graphql/trace_patcher'

require 'datadog'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::TracePatcher,
  skip: Gem::Version.new(::GraphQL::VERSION) < Gem::Version.new('2.0.19') do
    before(:context) { load_test_schema }
    after(:context) do
      unload_test_schema
      remove_patch!(:graphql)
    end

    describe '#patch!' do
      context 'with empty schema configuration' do
        it_behaves_like 'graphql default instrumentation' do
          before do
            Datadog.configure do |c|
              c.tracing.instrument :graphql
            end
          end
        end
      end

      context 'with specified schemas configuration' do
        it_behaves_like 'graphql default instrumentation' do
          before do
            Datadog.configure do |c|
              c.tracing.instrument :graphql, schemas: [TestGraphQLSchema]
            end
          end
        end
      end
    end
  end
