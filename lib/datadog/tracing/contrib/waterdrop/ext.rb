# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        module Ext
          ENV_ENABLED = 'DD_TRACE_WATERDROP_ENABLED'

          SPAN_PRODUCER = 'karafka.produce'

          TAG_PRODUCER = 'kafka.producer'
        end
      end
    end
  end
end
