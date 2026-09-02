# frozen_string_literal: true

module Datadog
  module AIGuard
    module Redaction
      SEGMENT_PATTERN = /\A([A-Za-z0-9_]+)(?:\[([0-9]+)\])?\z/

      def self.skipped(messages)
        Result.new(messages, applied: 0, failures: 0, performed: false)
      end

      def self.apply(messages, replacements:)
        return Result.new(messages, applied: 0, failures: 0, performed: true) unless messages.is_a?(::Array) && replacements
        return Result.new(messages, applied: 0, failures: 1, performed: true) unless replacements.is_a?(::Array)
        return Result.new(messages, applied: 0, failures: 0, performed: true) if replacements.empty?

        failures = 0
        by_path = {}
        conflicting = {}

        replacements.each do |entry|
          unless entry.is_a?(::Hash)
            failures += 1
            next
          end

          path = entry["path"]
          replacement = entry["replacement"]

          unless path.is_a?(::String) && !path.empty? && replacement.is_a?(::String)
            failures += 1
            next
          end

          next if conflicting[path]

          if by_path.key?(path) && by_path[path] != replacement
            by_path.delete(path)
            conflicting[path] = true
            failures += 1
            next
          end

          by_path[path] = replacement
        end

        edits = {}
        applied = 0

        by_path.each do |path, replacement|
          target = resolve(messages, path)

          unless target
            failures += 1
            next
          end

          index, kind, sub = target
          edit = (edits[index] ||= {parts: {}})

          case kind
          when :content then edit[:content] = replacement
          when :arguments then edit[:arguments] = replacement
          when :text then edit[:parts][sub] = replacement
          end

          applied += 1
        end

        return Result.new(messages, applied: 0, failures: failures, performed: true) if edits.empty?

        redacted = messages.each_with_index.map do |message, index|
          edit = edits[index]
          edit ? rebuild(message, edit) : message
        end

        Result.new(redacted, applied: applied, failures: failures, performed: true)
      rescue
        Result.new(messages, applied: 0, failures: 1, performed: true)
      end

      def self.resolve(messages, path)
        segments = path.split(".").map do |segment|
          match = SEGMENT_PATTERN.match(segment)
          match && [match[1], match[2]&.to_i]
        end
        return if segments.any?(&:nil?)

        first_name, index = segments.first
        return unless first_name == "messages" && index

        message = messages[index]
        return unless message

        if (tool_call = message.tool_call)
          return unless segments.length == 4 && segments[1] == ["tool_calls", 0] &&
            segments[2] == ["function", nil] && segments[3] == ["arguments", nil]
          return unless tool_call.arguments.is_a?(::String)

          [index, :arguments, nil]
        elsif message.content.is_a?(::Array)
          return unless segments.length == 3 && segments[1][0] == "content" &&
            segments[1][1] && segments[2] == ["text", nil]

          part = message.content[segments[1][1]]
          return unless part.is_a?(Evaluation::ContentPart::Text)

          [index, :text, segments[1][1]]
        else
          return unless segments.length == 2 && segments[1] == ["content", nil]
          return unless message.content.is_a?(::String)

          [index, :content, nil]
        end
      end

      def self.rebuild(message, edit)
        if edit.key?(:content)
          message.with_content(edit[:content])
        elsif edit.key?(:arguments)
          message.with_tool_call(message.tool_call.with_arguments(edit[:arguments]))
        else
          content = message.content.each_with_index.map do |part, index|
            edit[:parts].key?(index) ? part.with_text(edit[:parts][index]) : part
          end

          message.with_content(content)
        end
      end
    end
  end
end
