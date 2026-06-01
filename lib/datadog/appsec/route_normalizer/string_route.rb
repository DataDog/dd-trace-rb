# frozen_string_literal: true

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
      # @api private
      module StringRoute
        PARAM_TOKEN = /:\w+|(?<!\w)\*\w*/
        PARAM_SIGILS = /[:\*]/

        DISALLOWED_CHARS = %r{[^\w.~/-]}

        # Per-byte percent-encoding lookup, indexed by byte value (0-255)
        #
        # Example:
        #
        #  32 => %20   (space)
        #  33 => %21   (!)
        #  47 => /     (passthrough)
        #  65 => A     (passthrough)
        # 195 => %C3   (UTF-8 lead byte)
        # 169 => %A9   (UTF-8 continuation byte)
        BYTE_ENCODING_TABLE = Array.new(256) do |byte|
          char = byte.chr
          char.match?(DISALLOWED_CHARS) ? -('%%%02X' % byte) : -char
        end.freeze

        # Max bytes one input byte expands to as percent-encoded `%XX`
        MAX_ENCODED_BYTE_SIZE = 3

        module_function

        def normalize(route_pattern)
          nameless_counter = 0
          # NOTE: Flatten optional markers — reached without matched params
          #       (e.g. http.route fallback), so the optional can't be resolved
          #       and is kept as if present
          route = route_pattern.delete('()?')

          result = route.split('/', -1).each_with_object(+'') do |segment, memo|
            memo << '/' unless memo.empty? && segment.empty?
            next if segment.empty?

            next memo << encode_static(segment) unless segment.match?(PARAM_SIGILS)

            tokens = segment.scan(PARAM_TOKEN)
            next memo << encode_static(segment) if tokens.empty?

            names = tokens.map { |token| (token.length > 1) ? token[1..-1] : "param#{nameless_counter += 1}" }
            memo << "{#{names.join('+')}}"
          end

          result = "/#{result}" unless result.start_with?('/')
          result
        end

        def encode_static(text)
          return text unless text.match?(DISALLOWED_CHARS)

          buffer = String.new(capacity: text.bytesize * MAX_ENCODED_BYTE_SIZE, encoding: Encoding::UTF_8)
          text.each_byte { |byte| buffer << BYTE_ENCODING_TABLE.fetch(byte) }
          buffer
        # NOTE: Defensive only — this can never happen. {String#each_byte} yields
        #       integers in 0-255 and {BYTE_ENCODING_TABLE} has an entry for every one
        rescue IndexError => e
          AppSec.telemetry&.report(e, description: 'AppSec: Route segment byte outside 0-255 encoding table')
          '~invalid~'
        end
      end
    end
  end
end
