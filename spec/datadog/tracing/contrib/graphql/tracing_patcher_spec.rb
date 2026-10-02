require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/graphql/test_schema_examples"
require "datadog/tracing/contrib/graphql/tracing_patcher"

require "datadog"

RSpec.describe Datadog::Tracing::Contrib::GraphQL::TracingPatcher do
  describe "#patch!" do
    before do
      Datadog.configuration.tracing[:graphql].reset!
    end

    # The patcher only runs once per context, so each context gets its own schema class and
    # patch; otherwise the context that runs first would decide the tracer configuration for
    # the whole file.

    context "with empty schema configuration" do
      before(:context) { load_test_schema }
      after(:context) do
        unload_test_schema
        remove_patch!(:graphql)
        # `TracingPatcher#patch!` appends a `DataDogTracing` instance to the global
        # `GraphQL::Schema` tracers; remove it so it cannot override the trace module
        # installed by the "with specified schemas" context.
        ::GraphQL::Schema.send(:own_tracers).reject! { |t| t.is_a?(::GraphQL::Tracing::DataDogTracing) }
      end

      it_behaves_like "graphql default instrumentation", legacy_output: true do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :graphql, with_deprecated_tracer: true
          end
        end
      end
    end

    context "with specified schemas configuration" do
      before(:context) { load_test_schema }
      after(:context) do
        unload_test_schema
        remove_patch!(:graphql)
      end

      it_behaves_like "graphql default instrumentation" do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :graphql, with_deprecated_tracer: true, schemas: [TestGraphQLSchema]
          end
        end
      end
    end
  end
end
