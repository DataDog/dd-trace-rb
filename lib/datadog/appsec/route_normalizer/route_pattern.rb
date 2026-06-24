# frozen_string_literal: true

require_relative 'route_text'

module Datadog
  module AppSec
    module RouteNormalizer
      # Normalizes a route spec pattern into the normalized route format,
      # inspired by OpenAPI v3 path templating (best effort)
      #
      # Example:
      #
      #   /users/:id           => /users/{id}
      #   /photos/:id.:format  => /photos/{id+format}
      #   /posts/:id(.:format) => /posts/{id+format}
      #   /files/*path         => /files/{path}
      #   /hello world         => /hello%20world
      #
      # NOTE: When a request path is supplied, optional groups `(...)` are resolved
      #       against it: a group is kept only when the path actually matched it.
      #
      # NOTE: Without a request path (or for paths longer than {MAX_RESOLVE_LENGTH}),
      #       optional markers are flattened and kept as if present.
      #
      # @api private
      class RoutePattern
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

        PARAM_NAME_CHARS = [*'a'..'z', *'A'..'Z', *'0'..'9', '_'].join

        EXCLUDED_PARAM_NAME_TERMINATOR_CHARS = [
          PARAM_NAME_CHARS,
          PATTERN_STRUCTURE_CHARS
        ].join

        MAX_RESOLVE_LENGTH = 8192

        Checkpoint = Struct.new(:resolved_length, :pattern_index, :path_index)

        # Param sigils mark where dynamic route syntax may start
        #
        # Example:
        #
        #   users    -> no
        #   :id      -> yes
        #   user-:id -> yes
        #   *        -> yes
        #   foo:     -> yes, validated later by {PARAM_TOKENS}
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
              if token.length > 1
                token[1..-1]
              else
                "param#{nameless_counter += 1}"
              end
            end

            memo << "{#{names.join('+')}}"
          end

          result.start_with?('/') ? result : "/#{result}"
        end

        private

        # Optional resolution walks the route pattern and request path together
        #
        # Example:
        #
        #   pattern: /posts/:id(.:format)
        #   path:    /posts/1.json
        #                    ^
        #                    `.` matches, so the optional group is kept
        #
        #   pattern: /posts/:id(.:format)
        #   path:    /posts/1
        #                   ^
        #                   path ended before `.`, so the optional group is skipped
        #
        # Checkpoints let optional groups fail after a partial match
        #
        #   pattern: /posts(/:id)/edit
        #   path:    /posts/edit
        #                 ^
        #                 `(/:id)` starts like `/edit`, so a checkpoint is saved
        #
        #   pattern: /posts(/:id)/edit
        #   path:    /posts/edit
        #                 ^
        #                 `:id` cannot consume `edit`, so we rewind after `(/:id)`
        def resolve_pattern_optionals(request_path)
          return @pattern if !@pattern.include?(GROUP_OPEN_CHAR) && !@pattern.include?(OPTIONAL_GROUP_SUFFIX_CHAR)

          unless resolve_pattern_optionals?(request_path)
            return remove_optional_group_sigils(@pattern) if @pattern.include?(GROUP_OPEN_CHAR)

            return @pattern
          end

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
              #       Example: `/posts/edit` request path starts like `(/:id)` in pattern
              #                `/posts(/:id)/edit`, but `:id` must be skipped
              if @path_index < @path_length && @request_path[@path_index] == @pattern[@pattern_index + 1]
                checkpoints << Checkpoint.new(resolved.length, optional_group_end_index + 1, @path_index)
                @pattern_index += 1
              else
                @pattern_index = optional_group_end_index + 1
              end
            when GROUP_CLOSE_CHAR
              @pattern_index += 1
              @pattern_index += 1 if @pattern[@pattern_index] == OPTIONAL_GROUP_SUFFIX_CHAR
            when OPTIONAL_GROUP_SUFFIX_CHAR
              @pattern_index += 1
            when NAMED_PARAM_PREFIX_CHAR
              param_name_end_index = find_next_param_name_end_index

              # NOTE: A ':' without a param name is literal text
              #       Example: `/foo:` must match a literal `:`, not a param
              if param_name_end_index == @pattern_index + 1
                unless expected_path_char?(NAMED_PARAM_PREFIX_CHAR)
                  checkpoint = restore_checkpoint!(resolved, checkpoints)
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

              # NOTE: A trailing `?` makes the param optional
              #       Example: `/posts/:id.?:format?` with `/posts/1` skips `:format?`
              if @pattern[param_name_end_index] == OPTIONAL_GROUP_SUFFIX_CHAR && @path_index >= @path_length
                @pattern_index = param_name_end_index + 1
                next
              end

              resolved << @pattern[@pattern_index...param_name_end_index]

              terminator_char = find_param_value_terminator_char(param_name_end_index: param_name_end_index)
              @path_index = find_param_value_end_index(terminator_char: terminator_char)

              @pattern_index = param_name_end_index
            when GLOB_PARAM_PREFIX_CHAR
              param_name_end_index = find_next_param_name_end_index
              terminator_char = find_param_value_terminator_char(param_name_end_index: param_name_end_index)

              resolved << @pattern[@pattern_index...param_name_end_index]

              @path_index = find_glob_value_end_index(terminator_char: terminator_char)
              @pattern_index = param_name_end_index
            else
              unless expected_path_char?(char)
                if @pattern[@pattern_index + 1] == OPTIONAL_GROUP_SUFFIX_CHAR
                  @pattern_index += 2
                  next
                end

                checkpoint = restore_checkpoint!(resolved, checkpoints)
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

        def restore_checkpoint!(resolved, checkpoints)
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

        def find_param_value_terminator_char(param_name_end_index:)
          char = @pattern[param_name_end_index]

          if char == GROUP_OPEN_CHAR
            @pattern[param_name_end_index + 1]
          else
            char
          end
        end

        def find_param_value_end_index(terminator_char:)
          terminator_indexes = []
          slash_index = @request_path.index('/', @path_index)
          dot_index = @request_path.index('.', @path_index)

          terminator_indexes << slash_index if slash_index
          terminator_indexes << dot_index if dot_index

          if terminator_char && !EXCLUDED_PARAM_NAME_TERMINATOR_CHARS.include?(terminator_char)
            custom_index = @request_path.index(terminator_char, @path_index)
            terminator_indexes << custom_index if custom_index
          end

          terminator_indexes.empty? ? @request_path.length : terminator_indexes.min
        end

        def find_glob_value_end_index(terminator_char:)
          return @path_length unless terminator_char
          return @path_length if EXCLUDED_PARAM_NAME_TERMINATOR_CHARS.include?(terminator_char)

          terminator_index = @request_path.rindex(terminator_char)
          return @path_length unless terminator_index && terminator_index >= @path_index

          terminator_index
        end

        def find_next_optional_group_end_index
          depth = 0
          index = @pattern_index

          while index < @pattern_length
            char = @pattern[index]
            depth += 1 if char == GROUP_OPEN_CHAR

            if char == GROUP_CLOSE_CHAR
              depth -= 1

              if depth.zero?
                next_index = index + 1

                return next_index if @pattern[next_index] == OPTIONAL_GROUP_SUFFIX_CHAR

                return index
              end
            end

            index += 1
          end

          index
        end
      end
    end
  end
end
