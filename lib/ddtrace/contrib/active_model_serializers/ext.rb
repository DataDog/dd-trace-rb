module Datadog
  module Contrib
    module ActiveModelSerializers
      # ActiveModelSerializers integration constants
      module Ext
        APP = 'active_model_serializers'.freeze
        SERVICE_NAME = 'active_model_serializers'.freeze

        SPAN_RENDER = 'active_model_serializers.render'.freeze
        SPAN_SERIALIZE = 'active_model_serializers.serialize'.freeze

        TAG_ADAPTER = 'active_model_serializers.adapter'.freeze
        TAG_SERIALIZER = 'active_model_serializers.serializer'.freeze
      end
    end
  end
end
