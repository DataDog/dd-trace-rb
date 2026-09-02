# frozen_string_literal: true

module Datadog
  module AIGuard
    module Redaction
      SEGMENT_PATTERN = /\A([A-Za-z0-9_]+)(?:\[([0-9]+)\])?\z/

      # Example inputs (AI Guard /evaluate contract):
      #
      #   messages = [
      #     {role: "user", content: "my ssn is 123-45-6789"},
      #     {role: "assistant", content: [{type: "text", text: "the secret is abc"}]},
      #     {role: "assistant", tool_calls: [{id: "1", function: {name: "f", arguments: "{\"ssn\":\"123\"}"}}]},
      #   ]
      #
      #   replacements = [
      #     {"path" => "messages[0].content", "replacement" => "my ssn is [REDACTED]"},
      #     {"path" => "messages[1].content[0].text", "replacement" => "the secret is [REDACTED]"},
      #     {"path" => "messages[2].tool_calls[0].function.arguments", "replacement" => "{\"ssn\":\"[REDACTED]\"}"},
      #   ]
      def self.skipped(messages)
        Result.new(messages, applied: 0, failures: 0, performed: false)
      end

      def self.redact(messages, replacements:)
        return Result.new(messages, applied: 0, failures: 0, performed: true) unless messages.is_a?(::Array) && replacements
        return Result.new(messages, applied: 0, failures: 1, performed: true) unless replacements.is_a?(::Array)
        return Result.new(messages, applied: 0, failures: 0, performed: true) if replacements.empty?

        failures = 0
        by_path = {}
        conflicting = {}

        # Validate and dedup: keep one replacement per path; a path asked to become two
        # different strings is dropped as a conflict.
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

        root = {messages: messages}
        targets = []

        # Resolve every path to a writable string slot. Two passes: collect first, write
        # after, so a later failure never leaves a half-redacted payload.
        by_path.each do |path, replacement|
          # "messages[0].content[1].text" => [["messages", 0], ["content", 1], ["text", nil]]
          segments = path.split(".").map do |segment|
            match = SEGMENT_PATTERN.match(segment)
            match && [match[1], match[2]&.to_i]
          end

          first_name, first_index = segments.first
          allowed =
            segments.none?(&:nil?) && first_name == "messages" && first_index && (
              (segments.length == 2 && segments[1] == ["content", nil]) ||
              (segments.length == 3 && segments[1][0] == "content" && segments[1][1] && segments[2] == ["text", nil]) ||
              (segments.length == 4 && segments[1][0] == "tool_calls" && segments[1][1] &&
                segments[2] == ["function", nil] && segments[3] == ["arguments", nil])
            )

          unless allowed
            failures += 1
            next
          end

          node = root
          reached = true
          segments[0...-1].each do |name, index|
            key = name.to_sym
            unless node.is_a?(::Hash) && node.key?(key)
              reached = false
              break
            end

            node = node[key]
            if index
              unless node.is_a?(::Array) && index < node.length
                reached = false
                break
              end

              node = node[index]
            end
          end

          terminal = segments.last[0].to_sym
          unless reached && node.is_a?(::Hash) && node[terminal].is_a?(::String)
            failures += 1
            next
          end

          targets << [node, terminal, replacement]
        end

        targets.each { |container, key, replacement| container[key] = replacement }

        Result.new(messages, applied: targets.size, failures: failures, performed: true)
      rescue
        Result.new(messages, applied: 0, failures: 1, performed: true)
      end
    end
  end
end
