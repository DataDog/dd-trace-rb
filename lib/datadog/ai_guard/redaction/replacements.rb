# frozen_string_literal: true

require "forwardable"

module Datadog
  module AIGuard
    module Redaction
      # Converts raw backend redaction replacements into a conflict-free
      # path-to-replacement map
      #
      # @api private
      class Replacements
        extend Forwardable

        TEXT_PATH_PATTERN = /\Amessages\[([0-9]+)\]\.content\[([0-9]+)\]\.text\z/
        CONTENT_PATH_PATTERN = /\Amessages\[([0-9]+)\]\.content\z/
        # NOTE: `Datadog::AIGuard::Evaluation::Message` has at most one tool call,
        #       serialized as a one-element array. Only index zero is valid, and
        #       zero-padded forms such as `[00]` are accepted
        ARGUMENTS_PATH_PATTERN = /\Amessages\[([0-9]+)\]\.tool_calls\[0+\]\.function\.arguments\z/

        def_delegator :@replacements, :each

        attr_reader :failures

        def initialize(raw_replacements)
          @failures = 0
          @replacements = build(raw_replacements)
        end

        private

        # NOTE: Identical duplicates collapse into a single entry,
        #       conflicting replacements remove the path and record one failure,
        #       and malformed or unsupported entries are skipped and counted individually
        #
        # Examples
        #
        #   translates this
        #
        #   [
        #     {"path" => "messages[0].content", "replacement" => "<redacted>"},
        #     {"path" => "messages[1].content[2].text", "replacement" => "<redacted>"},
        #     {"path" => "messages[2].tool_calls[0].function.arguments", "replacement" => "{}"}
        #   ]
        #
        #   into this
        #
        #   {
        #     [0, :content] => "<redacted>",
        #     [1, :text, 2] => "<redacted>",
        #     [2, :arguments] => "{}"
        #   }
        def build(raw_replacements)
          unless raw_replacements.is_a?(::Array)
            @failures += 1
            return {}
          end

          conflicted = {}
          raw_replacements.each_with_object({}) do |entry, replacements|
            next @failures += 1 unless entry.is_a?(::Hash)

            raw_path = entry["path"]
            replacement = entry["replacement"]

            if !raw_path.is_a?(::String) || raw_path.empty? || !replacement.is_a?(::String)
              next @failures += 1
            end

            path =
              if (match = CONTENT_PATH_PATTERN.match(raw_path))
                [match[1].to_i, :content]
              elsif (match = TEXT_PATH_PATTERN.match(raw_path))
                [match[1].to_i, :text, match[2].to_i]
              elsif (match = ARGUMENTS_PATH_PATTERN.match(raw_path))
                [match[1].to_i, :arguments]
              end

            next @failures += 1 unless path
            next if conflicted.key?(path)

            if replacements.key?(path)
              next if replacements[path] == replacement

              replacements.delete(path)
              conflicted[path] = true

              next @failures += 1
            end

            replacements[path] = replacement
          end
        end
      end
    end
  end
end
