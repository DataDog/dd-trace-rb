require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/graphql/test_schema_examples'
require 'datadog/tracing/contrib/graphql/tracing_patcher'
require 'datadog/tracing/contrib/graphql/trace_patcher'

require 'datadog'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::Patcher do
  around do |example|
    remove_patch!(:graphql)
    Datadog.configuration.reset!
    Datadog.configuration.tracing[:graphql].reset!

    without_warnings do
      example.run
    end

    remove_patch!(:graphql)
    Datadog.configuration.reset!
    Datadog.configuration.tracing[:graphql].reset!
  end

  describe 'patch' do
    context 'when graphql does not support trace' do
      context 'with default configuration' do
        it 'patches GraphQL' do
          allow(Datadog::Tracing::Contrib::GraphQL::Integration).to receive(:trace_supported?).and_return(true)
          expect(Datadog::Tracing::Contrib::GraphQL::TracePatcher).to receive(:patch!).with(
            [],
            hash_including(:analytics_enabled, :analytics_sample_rate, :service)
          )

          Datadog.configure do |c|
            c.tracing.instrument :graphql
          end
        end
      end

      context 'with with_deprecated_tracer enabled' do
        it do
          allow(Datadog::Tracing::Contrib::GraphQL::Integration).to receive(:trace_supported?).and_return(true)
          expect(Datadog::Tracing::Contrib::GraphQL::TracingPatcher).to receive(:patch!).with(
            [],
            hash_including(:analytics_enabled, :analytics_sample_rate, :service)
          )

          Datadog.configure do |c|
            c.tracing.instrument :graphql, with_deprecated_tracer: true
          end
        end
      end

      context 'with with_deprecated_tracer disabled' do
        it do
          allow(Datadog::Tracing::Contrib::GraphQL::Integration).to receive(:trace_supported?).and_return(true)
          expect(Datadog::Tracing::Contrib::GraphQL::TracePatcher).to receive(:patch!).with(
            [],
            hash_including(:analytics_enabled, :analytics_sample_rate, :service)
          )

          Datadog.configure do |c|
            c.tracing.instrument :graphql, with_deprecated_tracer: false
          end
        end
      end

      context 'with given schema' do
        it do
          allow(Datadog::Tracing::Contrib::GraphQL::Integration).to receive(:trace_supported?).and_return(true)
          expect(Datadog::Tracing::Contrib::GraphQL::TracePatcher).to receive(:patch!).with(
            [TestGraphQLSchema],
            hash_including(:analytics_enabled, :analytics_sample_rate, :service)
          )

          Datadog.configure do |c|
            c.tracing.instrument :graphql, schemas: [TestGraphQLSchema]
          end
        end
      end
    end

    context 'when graphql supports trace' do
      context 'with default configuration' do
        it 'patches GraphQL' do
          allow(Datadog::Tracing::Contrib::GraphQL::Integration).to receive(:trace_supported?).and_return(false)
          expect(Datadog::Tracing::Contrib::GraphQL::TracingPatcher).to receive(:patch!).with(
            [],
            hash_including(:analytics_enabled, :analytics_sample_rate, :service)
          )
          expect_any_instance_of(Datadog::Core::Logger).to receive(:warn)
            .with(/Falling back to GraphQL::Tracing::DataDogTracing/)

          Datadog.configure do |c|
            c.tracing.instrument :graphql
          end
        end
      end

      context 'with with_deprecated_tracer enabled' do
        it do
          allow(Datadog::Tracing::Contrib::GraphQL::Integration).to receive(:trace_supported?).and_return(false)
          expect(Datadog::Tracing::Contrib::GraphQL::TracingPatcher).to receive(:patch!).with(
            [],
            hash_including(:analytics_enabled, :analytics_sample_rate, :service)
          )
          expect_any_instance_of(Datadog::Core::Logger).not_to receive(:warn)

          Datadog.configure do |c|
            c.tracing.instrument :graphql, with_deprecated_tracer: true
          end
        end
      end

      context 'with with_deprecated_tracer disabled' do
        it do
          allow(Datadog::Tracing::Contrib::GraphQL::Integration).to receive(:trace_supported?).and_return(false)
          expect(Datadog::Tracing::Contrib::GraphQL::TracingPatcher).to receive(:patch!).with(
            [],
            hash_including(:analytics_enabled, :analytics_sample_rate, :service)
          )
          expect_any_instance_of(Datadog::Core::Logger).to receive(:warn)
            .with(/Falling back to GraphQL::Tracing::DataDogTracing/)

          Datadog.configure do |c|
            c.tracing.instrument :graphql, with_deprecated_tracer: false
          end
        end
      end

      context 'with given schema' do
        it do
          allow(Datadog::Tracing::Contrib::GraphQL::Integration).to receive(:trace_supported?).and_return(false)
          expect(Datadog::Tracing::Contrib::GraphQL::TracingPatcher).to receive(:patch!).with(
            [TestGraphQLSchema],
            hash_including(:analytics_enabled, :analytics_sample_rate, :service)
          )
          expect_any_instance_of(Datadog::Core::Logger).to receive(:warn)
            .with(/Falling back to GraphQL::Tracing::DataDogTracing/)

          Datadog.configure do |c|
            c.tracing.instrument :graphql, schemas: [TestGraphQLSchema]
          end
        end
      end
    end
  end
end
