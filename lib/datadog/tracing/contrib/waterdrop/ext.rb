# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        module Ext
          ENV_ENABLED = 'DD_TRACE_WATERDROP_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_WATERDROP_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_WATERDROP_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_WATERDROP_ANALYTICS_SAMPLE_RATE'.freeze

          # Span names
          SPAN_PRODUCE = 'kafka.produce'.freeze

          # Tags
          TAG_TOPIC = 'kafka.topic'.freeze
          TAG_PARTITION = 'kafka.partition'.freeze
          TAG_OFFSET = 'kafka.offset'.freeze
          TAG_MESSAGE_KEY = 'kafka.message_key'.freeze
          TAG_SYSTEM = 'kafka'.freeze

          # Component and operation tags
          TAG_COMPONENT = 'waterdrop'.freeze
          TAG_OPERATION_PRODUCE = 'produce'.freeze

          # Default service name
          DEFAULT_SERVICE_NAME = 'kafka'.freeze
        end
      end
    end
  end
end
