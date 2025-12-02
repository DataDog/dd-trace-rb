# frozen_string_literal: true

module Datadog
  module AIGuard
    # Session class holds the LLM context
    class Session
      ROLES = %i[system developer user assistant].freeze

      attr_reader :messages

      def initialize(*messages)
        @messages = []

        # TODO: ensure this works with both string and symbol keys
        messages.each do |message|
          add_message(**message) if message.key?(:content)
          add_tool_call(**message) if message.key?(:tool_name)
          add_tool_output(**message) if message.key?(:tool_call_id)
        end
      end

      def add_message(role:, content:)
        unless ROLES.include?(role)
          raise ArgumentError, "Invalid role: #{role}, valid roles are: #{ROLES.join(', ')}"
        end

        @messages << {role: role, content: truncate_content(content)}
      end

      def add_tool_call(id:, tool_name:, arguments:)
        # TODO: ensure id is a string
        tool_call = {id: id, tool_name: tool_name, arguments: arguments}

        if @messages.last&.key?(:tool_call)
          @messages.last[:tool_call] << tool_call
        else
          @messages << {role: :assistant, tool_calls: [tool_call]}
        end
      end

      def add_tool_output(tool_call_id:, output:)
        # TODO: ensure tool_call_id is a string
        @messages << {role: :tool, tool_call_id: tool_call_id, content: truncate_content(output)}
      end

      def system_prompt(content)
        add_message(role: :system, content: content)
      end

      def developer_prompt(content)
        add_message(role: :developer, content: content)
      end

      def user_prompt(content)
        add_message(role: :user, content: content)
      end

      def assistant_response(content)
        add_message(role: :assistant, content: content)
      end

      def evaluate
        Evaluation::Request.new(self).perform
      end

      private

      def truncate_content(content)
        # TODO: truncate string to correct number of bytes
        content
      end
    end
  end
end
