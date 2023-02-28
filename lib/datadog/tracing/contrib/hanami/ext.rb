module Datadog
  module Tracing
    module Contrib
      module Hanami
        # Hanami integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_HANAMI_ENABLED'.freeze

          SPAN_ACTION =  'hanami.action'.freeze
          SPAN_ROUTING = 'hanami.routing'.freeze
          SPAN_RENDER =  'hanami.render'.freeze

          TAG_COMPONENT = 'hanami'.freeze
          TAG_OPERATION_ACTION = 'action'.freeze
          TAG_OPERATION_ROUTING = 'routing'.freeze
          TAG_OPERATION_RENDER = 'render'.freeze
        end
      end
    end
  end
end
