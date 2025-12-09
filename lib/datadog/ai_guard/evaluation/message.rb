# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Message class for AI Guard
      class Message
        class InvalidRoleError < ArgumentError; end

        VALID_ROLES = %i[assistant tool system developer user].freeze

        attr_reader :role, :content, :tool_call, :tool_call_id

        def initialize(role:, content: nil, tool_call: nil, tool_call_id: nil)
          @role = role.to_sym
          @content = content
          @tool_call = tool_call
          @tool_call_id = tool_call_id

          unless VALID_ROLES.include?(@role)
            raise ArgumentError, %Q{Invalid role "#{role}", valid roles are: #{VALID_ROLES.join(", ")}}
          end
        end

        def tool_call?
          !!@tool_call
        end

        def tool_output?
          !!@tool_call_id
        end
      end
    end
  end
end
