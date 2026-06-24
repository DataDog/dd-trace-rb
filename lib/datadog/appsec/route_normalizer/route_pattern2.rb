# frozen_string_literal: true

require_relative 'route_text'

module Datadog
  module AppSec
    module RouteNormalizer
      # @api private
      class RoutePattern2
        GROUP_OPEN_CHAR = '('
        GROUP_CLOSE_CHAR = ')'

        OPTIONAL_GROUP_SUFFIX_CHAR = '?'
        OPTIONAL_GROUP_SIGILS = [
          GROUP_OPEN_CHAR,
          GROUP_CLOSE_CHAR,
          OPTIONAL_GROUP_SUFFIX_CHAR
        ].join

        NAMED_PARAM_PREFIX_CHAR = ':'
        GLOB_PARAM_PREFIX_CHAR = '*'

        PATTERN_STRUCTURE_CHARS = [
          NAMED_PARAM_PREFIX_CHAR,
          GLOB_PARAM_PREFIX_CHAR,
          GROUP_OPEN_CHAR,
          GROUP_CLOSE_CHAR
        ].join

        MAX_RESOLVE_LENGTH = 8192

        Checkpoint = Struct.new(:resolved_length, :pattern_index, :path_index)

        # Param sigils mark where dynamic route syntax may start
        #
        #  users    -> no
        #  :id      -> yes
        #  user-:id -> yes
        #  *        -> yes
        #  foo:     -> yes, validated later by {PARAM_TOKENS}
        PARAM_START_SIGILS = /[:\*]/
        PARAM_TOKENS = /:\w+|(?<!\w)\*\w*/

        def initialize(pattern)
          @pattern = pattern
        end

        def normalize(request_path: nil)
          @path_index = 0
          @pattern_index = 0

          @request_path = request_path
          @path_length = request_path ? request_path.length : 0
          @pattern_length = @pattern.length

          nameless_counter = 0
          pattern = resolve_pattern_optionals(request_path)

          result = pattern.split('/', -1).each_with_object(+'') do |segment, memo|
            memo << '/' unless memo.empty? && segment.empty?
            next if segment.empty?

            unless segment.match?(PARAM_START_SIGILS)
              memo << RouteText.escape(segment)
              next
            end

            tokens = segment.scan(PARAM_TOKENS)

            if tokens.empty?
              memo << RouteText.escape(segment)
              next
            end

            names = tokens.map do |token|
              token.length > 1 ? token[1..-1] : "param#{nameless_counter += 1}"
            end

            memo << "{#{names.join('+')}}"
          end

          result.start_with?('/') ? result : "/#{result}"
        end

        private

        def resolve_pattern_optionals(request_path)
          return @pattern unless @pattern.include?(GROUP_OPEN_CHAR)
          return remove_optional_group_sigils(@pattern) unless resolve_pattern_optionals?(request_path)

          resolved = +''
          checkpoints = []

          while @pattern_index < @pattern_length
            char = @pattern[@pattern_index]

            case char
            when GROUP_OPEN_CHAR
              optional_group_end_index = find_next_optional_group_end_index

              # NOTE: The request path may share the optional group's first char
              #       with the next required segment
              #
              #       Example:
              #         `/posts/edit` request path starts like `(/:id)` in pattern
              #         `/posts(/:id)/edit`, but `:id` must be skipped
              if @path_index < @path_length && @request_path[@path_index] == @pattern[@pattern_index + 1]
                checkpoints << Checkpoint.new(resolved.length, optional_group_end_index + 1, @path_index)
                @pattern_index += 1
              else
                @pattern_index = optional_group_end_index + 1
              end
            when GROUP_CLOSE_CHAR
              @pattern_index += 1
              @pattern_index += 1 if @pattern[@pattern_index] == OPTIONAL_GROUP_SUFFIX_CHAR
            when NAMED_PARAM_PREFIX_CHAR
              param_name_end_index = find_next_param_name_end_index

              # NOTE: A ':' without a param name is literal text
              #
              #       Example:
              #         `/foo:` must match a literal `:`, not a param
              if param_name_end_index == @pattern_index + 1
                if !expected_path_char?(NAMED_PARAM_PREFIX_CHAR)
                  checkpoint = restore_checkpoint(resolved, checkpoints)
                  return remove_optional_group_sigils(@pattern) unless checkpoint

                  @pattern_index = checkpoint.pattern_index
                  @path_index = checkpoint.path_index

                  next
                end

                @path_index += 1
                @pattern_index += 1
                resolved << NAMED_PARAM_PREFIX_CHAR

                next
              end

              resolved << @pattern[@pattern_index...param_name_end_index]

              stop_at_char = find_param_value_stop_char(param_name_end_index: param_name_end_index)
              @path_index = find_param_value_end_index(stop_at_char: stop_at_char)

              @pattern_index = param_name_end_index
            when GLOB_PARAM_PREFIX_CHAR
              param_name_end_index = find_next_param_name_end_index

              resolved << @pattern[@pattern_index...param_name_end_index]
              @path_index = @path_length
              @pattern_index = param_name_end_index
            else
              if !expected_path_char?(char)
                checkpoint = restore_checkpoint(resolved, checkpoints)
                return remove_optional_group_sigils(@pattern) unless checkpoint

                @pattern_index = checkpoint.pattern_index
                @path_index = checkpoint.path_index

                next
              end

              resolved << char
              @path_index += 1
              @pattern_index += 1
            end
          end

          resolved
        end

        def resolve_pattern_optionals?(request_path)
          request_path && @path_length <= MAX_RESOLVE_LENGTH
        end

        def expected_path_char?(char)
          @path_index < @path_length && @request_path[@path_index] == char
        end

        def restore_checkpoint(resolved, checkpoints)
          checkpoint = checkpoints.pop
          return unless checkpoint

          resolved.slice!(checkpoint.resolved_length..-1)
          checkpoint
        end

        def remove_optional_group_sigils(pattern)
          pattern.delete(OPTIONAL_GROUP_SIGILS)
        end

        def find_next_param_name_end_index
          current_index = @pattern_index + 1
          current_index += 1 while current_index < @pattern_length && @pattern[current_index].match?(/\w/)

          current_index
        end

        def find_param_value_stop_char(param_name_end_index:)
          char = @pattern[param_name_end_index]

          char == GROUP_OPEN_CHAR ? @pattern[param_name_end_index + 1] : char
        end

        def find_param_value_end_index(stop_at_char:)
          stops = []
          slash_index = @request_path.index('/', @path_index)
          dot_index = @request_path.index('.', @path_index)

          stops << slash_index if slash_index
          stops << dot_index if dot_index

          if stop_at_char && !stop_at_char.match?(/\w/) && !PATTERN_STRUCTURE_CHARS.include?(stop_at_char)
            custom_index = @request_path.index(stop_at_char, @path_index)
            stops << custom_index if custom_index
          end

          stops.empty? ? @request_path.length : stops.min
        end

        def find_next_optional_group_end_index
          depth = 0
          current_index = @pattern_index

          while current_index < @pattern_length
            char = @pattern[current_index]

            if char == GROUP_OPEN_CHAR
              depth += 1
            elsif char == GROUP_CLOSE_CHAR
              depth -= 1

              if depth.zero?
                next_index = current_index + 1

                return (@pattern[next_index] == OPTIONAL_GROUP_SUFFIX_CHAR) ? next_index : current_index
              end
            end

            current_index += 1
          end

          current_index
        end
      end
    end
  end
end
