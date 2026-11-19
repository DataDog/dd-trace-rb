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
        ARGUMENTS_PATH_PATTERN = /\Amessages\[([0-9]+)\]\.tool_calls\[([0-9]+)\]\.function\.arguments\z/

        def_delegators :@replacements, :each, :empty?

        attr_reader :failures_count

        def initialize(raw_replacements)
          @failures_count = 0
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
        #     [2, :arguments, 0] => "{}"
        #   }
        def build(raw_replacements)
          unless raw_replacements.is_a?(::Array)
            @failures_count += 1
            return {}
          end

          conflicting = {}
          raw_replacements.each_with_object({}) do |entry, replacements|
            next @failures_count += 1 unless entry.is_a?(::Hash)

            raw_path = entry["path"]
            replacement = entry["replacement"]

            if !raw_path.is_a?(::String) || raw_path.empty? || !replacement.is_a?(::String)
              next @failures_count += 1
            end

            # @type var path: Replacements::path?
            path =
              case raw_path
              when CONTENT_PATH_PATTERN
                [Regexp.last_match(1).to_i, :content]
              when TEXT_PATH_PATTERN
                [Regexp.last_match(1).to_i, :text, Regexp.last_match(2).to_i]
              when ARGUMENTS_PATH_PATTERN
                [Regexp.last_match(1).to_i, :arguments, Regexp.last_match(2).to_i]
              end

            next @failures_count += 1 unless path
            next if conflicting.key?(path)

            if replacements.key?(path)
              next if replacements[path] == replacement

              replacements.delete(path)
              conflicting[path] = true

              next @failures_count += 1
            end

            replacements[path] = replacement
          end
        end
      end
    end
  end
end
