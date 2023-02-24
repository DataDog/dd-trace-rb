require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'spec/datadog/tracing/contrib/active_model_serializers/helpers'
require 'spec/datadog/tracing/contrib/rails/support/deprecation'

require 'active_support/all'
require 'active_model_serializers'

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'ddtrace'
require 'datadog/tracing/contrib/active_model_serializers/patcher'

RSpec.describe 'ActiveModelSerializers patcher' do
  include_context 'AMS serializer'

  let(:configuration_options) { {} }

  before do
    # Supress active_model_serializers log output in the test run
    ActiveModelSerializersHelpers.disable_logging

    Datadog.configure do |c|
      c.tracing.instrument :active_model_serializers, configuration_options
    end

    raise_on_rails_deprecation!
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:active_model_serializers].reset_configuration!
    example.run
    Datadog.registry[:active_model_serializers].reset_configuration!
  end

  describe 'on render' do
    let(:test_obj) { TestModel.new(name: 'test object') }
    let(:serializer) { 'TestModelSerializer' }
    let(:adapter) { 'ActiveModelSerializers::Adapter::Attributes' }
    let(:event) { Datadog::Tracing::Contrib::ActiveModelSerializers::Patcher.send(:event_name) }
    let(:name) do
      if ActiveModelSerializersHelpers.ams_0_10_or_newer?
        Datadog::Tracing::Contrib::ActiveModelSerializers::Events::Render.span_name
      else
        Datadog::Tracing::Contrib::ActiveModelSerializers::Events::Serialize.span_name
      end
    end
    let(:operation_name) do
      if ActiveModelSerializersHelpers.ams_0_10_or_newer?
        Datadog::Tracing::Contrib::ActiveModelSerializers::Ext::TAG_OPERATION_RENDER
      else
        Datadog::Tracing::Contrib::ActiveModelSerializers::Ext::TAG_OPERATION_SERIALIZE
      end
    end

    let(:active_model_serializers_span) do
      spans.find { |s| s.name == name }
    end

    if ActiveModelSerializersHelpers.ams_0_10_or_newer?
      context 'when adapter is set' do
        subject(:render) { ActiveModelSerializers::SerializableResource.new(test_obj).serializable_hash }

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) do
            Datadog::Tracing::Contrib::ActiveModelSerializers::Ext::ENV_ANALYTICS_ENABLED
          end

          let(:analytics_sample_rate_var) do
            Datadog::Tracing::Contrib::ActiveModelSerializers::Ext::ENV_ANALYTICS_SAMPLE_RATE
          end

          let(:span) do
            render
            active_model_serializers_span
          end
        end

        it_behaves_like 'measured span for integration', true do
          let(:span) do
            render
            active_model_serializers_span
          end
        end

        it 'is expected to send a span' do
          render

          active_model_serializers_span.tap do |span|
            expect(span).to_not be_nil
            expect(span.name).to eq(name)
            expect(span.resource).to eq(serializer)
            expect(span.service).to eq(tracer.default_service)
            expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_TEMPLATE)
            expect(span.get_tag('active_model_serializers.serializer')).to eq(serializer)
            expect(span.get_tag('active_model_serializers.adapter')).to eq(adapter)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('active_model_serializers')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(operation_name)
          end
        end
      end
    end

    context 'when adapter is nil' do
      if ActiveModelSerializersHelpers.ams_0_10_or_newer?
        let(:render) { ActiveModelSerializers::SerializableResource.new(test_obj, adapter: nil).serializable_hash }

        it 'is expected to send a span with adapter tag equal to the model name' do
          render

          active_model_serializers_span.tap do |span|
            expect(span).to_not be_nil
            expect(span.name).to eq(name)
            expect(span.resource).to eq(serializer)
            expect(span.service).to eq(tracer.default_service)
            expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_TEMPLATE)
            expect(span.get_tag('active_model_serializers.serializer')).to eq(serializer)
            expect(span.get_tag('active_model_serializers.adapter')).to eq(test_obj.class.to_s)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('active_model_serializers')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(operation_name)
          end
        end
      else
        subject(:render) { TestModelSerializer.new(test_obj).as_json }

        it 'is expected to send a span with no adapter tag' do
          render

          active_model_serializers_span.tap do |span|
            expect(span).to_not be_nil
            expect(span.name).to eq(name)
            expect(span.resource).to eq(serializer)
            expect(span.service).to eq(tracer.default_service)
            expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_TEMPLATE)
            expect(span.get_tag('active_model_serializers.serializer')).to eq(serializer)
            expect(span.get_tag('active_model_serializers.adapter')).to be_nil
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('active_model_serializers')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(operation_name)
          end
        end
      end
    end
  end
end
