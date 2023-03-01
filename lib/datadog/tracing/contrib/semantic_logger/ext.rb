module Datadog
  module Tracing
    module Contrib
      module SemanticLogger
        # SemanticLogger integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_SEMANTIC_LOGGER_ENABLED'.freeze
        end
      end
    end
  end
end
