# frozen_string_literal: true

module Datadog
  module AIGuard
    class Evaluation
      # Tool call class for AI Guard
      class ToolCall
        attr_reader :tool_name, :id, :arguments

        def initialize(tool_name, id:, arguments:)
          @tool_name = tool_name
          @id = id
          @arguments = arguments
        end
      end
    end
  end
end
