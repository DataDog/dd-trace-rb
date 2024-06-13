require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/graphql/test_schema_examples'
require 'datadog/tracing/contrib/graphql/tracing_patcher'

require 'datadog'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::TracingPatcher do
  describe '#patch!' do
    context 'with empty schema configuration' do
      it_behaves_like 'graphql instrumentation' do
        before do
          described_class.patch!([], {})
        end
      end
    end

    context 'with specified schemas configuration' do
      it_behaves_like 'graphql instrumentation' do
        before do
          described_class.patch!([TestGraphQLSchema], {})
        end
      end
    end

    context 'when given something else' do
      it do
        expect_any_instance_of(Datadog::Core::Logger).to receive(:warn).with(/Unable to patch/)

        described_class.patch!([OpenStruct.new], {})
      end
    end
  end
end
