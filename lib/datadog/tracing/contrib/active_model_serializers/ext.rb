module Datadog
  module Tracing
    module Contrib
      module ActiveModelSerializers
        # ActiveModelSerializers integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_ACTIVE_MODEL_SERIALIZERS_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTIVE_MODEL_SERIALIZERS_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTIVE_MODEL_SERIALIZERS_ANALYTICS_SAMPLE_RATE'.freeze
          SPAN_RENDER = 'active_model_serializers.render'.freeze
          SPAN_SERIALIZE = 'active_model_serializers.serialize'.freeze
          TAG_ADAPTER = 'active_model_serializers.adapter'.freeze
          TAG_COMPONENT = 'active_model_serializers'.freeze
          TAG_OPERATION_RENDER = 'render'.freeze
          TAG_OPERATION_SERIALIZE = 'serialize'.freeze
          TAG_SERIALIZER = 'active_model_serializers.serializer'.freeze
        end
      end
    end
  end
end
