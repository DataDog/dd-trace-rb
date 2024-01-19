require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/graphql/test_schema_examples'

require 'ddtrace'
RSpec.describe 'GraphQL patcher' do
  # GraphQL generates tons of warnings.
  # This suppresses those warnings.
  around do |example|
    remove_patch!(:graphql)
    reset_schema_cache!(::GraphQL::Schema)
    reset_schema_cache!(TestGraphQLSchema)

    without_warnings do
      example.run
    end

    remove_patch!(:graphql)
    reset_schema_cache!(::GraphQL::Schema)
    reset_schema_cache!(TestGraphQLSchema)
  end

  describe 'class-based schema' do
    context 'with default configuration' do
      it_behaves_like 'graphql instrumentation' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :graphql
          end
        end
      end
    end

    context 'with specified schemas configuration' do
      it_behaves_like 'graphql instrumentation' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :graphql, schemas: [TestGraphQLSchema]
          end
        end
      end
    end
  end

  # Workaround to reset internal state
  def reset_schema_cache!(s)
    [
      '@own_tracers',
      '@trace_modes',
      '@trace_class',
      '@tracers',
      '@graphql_definition',
      '@own_trace_modes',
    ].each do |i_var|
      s.remove_instance_variable(i_var) if s.instance_variable_defined?(i_var)
    end
  end
end
