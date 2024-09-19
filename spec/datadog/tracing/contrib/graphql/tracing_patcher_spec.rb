require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/graphql/test_schema_examples'
require 'datadog/tracing/contrib/graphql/tracing_patcher'

require 'datadog'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::TracingPatcher do
  before(:context) { load_test_schema }
  after(:context) do
    unload_test_schema
    remove_patch!(:graphql)
  end

  describe '#patch!' do
    before do
      Datadog.configuration.tracing[:graphql].reset!
    end

    context 'with empty schema configuration' do
      it_behaves_like 'graphql default instrumentation' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :graphql, with_deprecated_tracer: true
          end
        end
      end
    end

    context 'with specified schemas configuration' do
      it_behaves_like 'graphql default instrumentation' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :graphql, with_deprecated_tracer: true, schemas: [TestGraphQLSchema]
          end
        end
      end
    end

    context 'when given something else' do
      before { remove_patch!(:graphql) }

      it do
        expect_any_instance_of(Datadog::Core::Logger).to receive(:warn).with(/Unable to patch/)

        Datadog.configure do |c|
          c.tracing.instrument :graphql, with_deprecated_tracer: true, schemas: [OpenStruct.new]
        end
      end
    end
  end
end
