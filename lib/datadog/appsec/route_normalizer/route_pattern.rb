# frozen_string_literal: true

require_relative 'route_text'

module Datadog
  module AppSec
    module RouteNormalizer
      # Normalizes a route spec string into the normalized route format,
      # inspired by OpenAPI v3 path templating.
      #
      # Example:
      #
      #   /users/:id           => /users/{id}
      #   /photos/:id.:format  => /photos/{id+format}
      #   /files/*path         => /files/{path}
      #   /posts/:id(.:format) => /posts/{id+format}
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
        PARAM_TOKEN = /:\w+|(?<!\w)\*\w*/
        PARAM_SIGILS = /[:\*]/
        WORD_CHAR = /\w/

        # A param value ends at the next segment boundary in the request path.
        SEGMENT_BOUNDARY = %r{[./]}

        # Pattern characters that are never custom segment delimiters: `.` and
        # `/` are the default boundaries, `():*` are structural.
        RESERVED_PATTERN_CHARS = '():*./'

        # Rails uses `(...)`; Mustermann uses `(...)?`.
        # Fallback keeps optional contents and removes only group markers.
        OPTIONAL_GROUP_MARKERS = '()?'

        # Upper bound on request path length we will scan to resolve optionals.
        # Beyond it we flatten instead, trading exactness for bounded work.
        MAX_RESOLVE_LENGTH = 8192

        def initialize(pattern)
          @pattern = pattern
          @fallback_pattern = if pattern.include?('(') || pattern.include?('?')
            pattern.delete(OPTIONAL_GROUP_MARKERS)
          else
            pattern
          end
        end

        def normalize(request_path: nil)
          if resolve_optionals?(request_path)
            resolved = resolve_optionals(request_path)
            return render_pattern(resolved) if resolved
          end

          render_pattern(@fallback_pattern)
        end

        private

        def resolve_optionals?(request_path)
          request_path && @pattern.include?('(') && request_path.length <= MAX_RESOLVE_LENGTH
        end

        def render_pattern(pattern)
          nameless_counter = 0

          result = pattern.split('/', -1).each_with_object(+'') do |segment, memo|
            memo << '/' unless memo.empty? && segment.empty?
            next if segment.empty?

            next memo << RouteText.escape(segment) unless segment.match?(PARAM_SIGILS)

            tokens = segment.scan(PARAM_TOKEN)
            next memo << RouteText.escape(segment) if tokens.empty?

            names = tokens.map do |token|
              (token.length > 1) ? token[1..-1] : "param#{nameless_counter += 1}"
            end

            memo << "{#{names.join('+')}}"
          end

          result.start_with?('/') ? result : "/#{result}"
        end

        # Walks the route pattern and the request path together, dropping
        # optional groups the path did not match. Returns the resolved pattern
        # string, or nil when the path diverges from the pattern (caller then
        # flattens). Backtrack-free: each character of both strings is visited
        # at most once and param values are skipped via C-level String#index.
        def resolve_optionals(request_path)
          resolved = +''
          pattern_pos = 0
          url_pos = 0
          pattern_len = @pattern.length
          url_len = request_path.length

          while pattern_pos < pattern_len
            char = @pattern[pattern_pos]

            case char
            when '('
              if url_pos < url_len && request_path[url_pos] == @pattern[pattern_pos + 1]
                pattern_pos += 1
              else
                pattern_pos = skip_group(pattern_pos)
              end
            when ')'
              pattern_pos += 1
            when ':', '*'
              name_end = pattern_pos + 1
              name_end += 1 while name_end < pattern_len && WORD_CHAR.match?(@pattern[name_end])

              if char == ':' && name_end == pattern_pos + 1
                return unless url_pos < url_len && request_path[url_pos] == ':'

                resolved << ':'
                url_pos += 1
                pattern_pos += 1
              else
                resolved << @pattern[pattern_pos...name_end]
                url_pos = (char == '*') ? url_len : consume_value(request_path, url_pos, @pattern[name_end])
                pattern_pos = name_end
              end
            else
              return unless url_pos < url_len && request_path[url_pos] == char

              resolved << char
              url_pos += 1
              pattern_pos += 1
            end
          end

          resolved
        end

        def consume_value(request_path, from, next_pattern_char)
          default_stop = request_path.index(SEGMENT_BOUNDARY, from) || request_path.length
          return default_stop unless custom_delimiter?(next_pattern_char)

          custom_stop = request_path.index(next_pattern_char, from) || request_path.length
          (custom_stop < default_stop) ? custom_stop : default_stop
        end

        def custom_delimiter?(char)
          return false if char.nil?
          return false if WORD_CHAR.match?(char)

          !RESERVED_PATTERN_CHARS.include?(char)
        end

        def skip_group(open_pos)
          depth = 0
          pos = open_pos
          length = @pattern.length

          while pos < length
            case @pattern[pos]
            when '(' then depth += 1
            when ')'
              depth -= 1
              return pos + 1 if depth.zero?
            end
            pos += 1
          end

          pos
        end
      end
    end
  end
end
