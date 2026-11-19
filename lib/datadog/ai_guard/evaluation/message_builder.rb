# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Builds a message from content parts and tool calls
      #
      # @public_api
      class MessageBuilder
        attr_reader :content, :tool_calls

        def initialize
          @content = []
          @tool_calls = []
        end

        def text(text)
          @content << ContentPart::Text.new(text)
        end

        def image_url(url)
          @content << ContentPart::ImageURL.new(url)
        end

        def tool_call(name:, id:, arguments:)
          @tool_calls << ToolCall.new(name, id: id.to_s, arguments: arguments)
        end
      end
    end
  end
end
