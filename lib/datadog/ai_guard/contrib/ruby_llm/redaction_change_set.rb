# frozen_string_literal: true

require "json"
require "stringio"

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # Changes required to redact a RubyLLM message
        #
        # @api private
        class RedactionChangeSet
          def initialize(original_message, redacted_message)
            @content_replacement = content_replacement(original_message.content, redacted_message.content)
            @content_part_replacements = content_part_replacements(original_message.content, redacted_message.content)
            @tool_call_replacements = tool_call_replacements(original_message.tool_calls, redacted_message.tool_calls)
          end

          def apply_to(message)
            return message unless changed?

            content = build_content(message)
            attachments = build_attachments(message)
            tool_calls = build_tool_calls(message)

            changed_message = ::RubyLLM::Message.new(
              content: content, attachments: attachments, tool_calls: tool_calls,
              role: message.role, model: message.model, tool_call_id: message.tool_call_id,
              raw: message.raw, thinking: message.thinking, citations: message.citations,
              finish_reason: message.finish_reason, server_tool_calls: message.server_tool_calls,
              raw_reasoning: message.raw_reasoning, cache_until_here: message.cache_until_here?
            )
            changed_message.conversation = message.conversation
            changed_message
          end

          private

          def content_replacement(original_content, redacted_content)
            return if original_content.is_a?(Array) || redacted_content == original_content

            redacted_content
          end

          def content_part_replacements(original_content, redacted_content)
            return {} unless original_content.is_a?(Array)

            replacements = {}
            original_content.each_with_index do |content_part, index|
              next if content_part == redacted_content[index]

              replacements[index] = redacted_content[index]
            end

            replacements
          end

          def tool_call_replacements(original_tool_calls, redacted_tool_calls)
            replacements = {}
            original_tool_calls.each_with_index do |tool_call, index|
              next if redacted_tool_calls[index] == tool_call

              replacements[tool_call.id] = redacted_tool_calls[index]
            end

            replacements
          end

          def changed?
            !!@content_replacement || !@content_part_replacements.empty? ||
              !@tool_call_replacements.empty?
          end

          def build_content(message)
            return @content_replacement if @content_replacement
            return message.content if message.content.to_s.empty?

            replacement = @content_part_replacements[0]
            replacement ? replacement.text : message.content
          end

          def build_attachments(message)
            return message.attachments if @content_part_replacements.empty?

            content_part_index = message.content.to_s.empty? ? 0 : 1
            attachments = nil

            message.attachments.each_with_index do |attachment, attachment_index|
              next if attachment.provider_file?
              next unless attachment.type == :text || attachment.type == :image

              replacement = @content_part_replacements[content_part_index]
              content_part_index += 1

              next unless replacement && attachment.type == :text

              attachments ||= message.attachments.dup
              attachments[attachment_index] = ::RubyLLM::Attachment.new(
                StringIO.new(replacement.text), filename: attachment.filename, config: attachment.config
              )
            end

            attachments || message.attachments
          end

          def build_tool_calls(message)
            return message.tool_calls if @tool_call_replacements.empty?

            tool_calls = message.tool_calls.dup
            @tool_call_replacements.each do |id, replacement|
              tool_call = tool_calls.fetch(id)
              tool_calls[id] = ::RubyLLM::ToolCall.new(
                id: tool_call.id, name: tool_call.name, remote: tool_call.remote?,
                thought_signature: tool_call.thought_signature,
                arguments: JSON.parse(replacement.arguments)
              )
            end

            tool_calls
          end
        end
      end
    end
  end
end
