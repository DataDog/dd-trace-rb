# frozen_string_literal: true

module Datadog
  module AppSec
    module RouteNormalizer
      # TODO: Write description
      #
      # @api private
      module StringRoute
        DYNAMIC_TOKEN = /:\w+|(?<!\w)\*\w*/
        HAS_DYNAMIC = /[:\*]/

        # TODO: Rename it and change pattern to use \w and such
        ENCODE_PATTERN = %r{[^A-Za-z0-9.\-~_/]}

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
          char.match?(ENCODE_PATTERN) ? -('%%%02X' % byte) : -char
        end.freeze

        # Max bytes one input byte expands to as percent-encoded `%XX`
        MAX_ENCODED_BYTE_SIZE = 3

        module_function

        def encode_static(text)
          return text unless text.match?(ENCODE_PATTERN)

          buffer = String.new(capacity: text.bytesize * MAX_ENCODED_BYTE_SIZE, encoding: Encoding::UTF_8)
          text.each_byte { |byte| buffer << BYTE_ENCODING_TABLE.fetch(byte) }
          buffer
        # NOTE: Defensive only — this can never happen. {String#each_byte} yields
        #       integers in 0-255 and {BYTE_ENCODING_TABLE} has an entry for every one
        rescue IndexError => e
          AppSec.telemetry&.report(e, description: 'AppSec: Route segment byte outside 0-255 encoding table')
          '~invalid~'
        end

        def normalize(route_pattern)
          nameless_counter = 0
          route = route_pattern.delete('()?')

          result = route.split('/', -1).each_with_object(+'') do |segment, memo|
            memo << '/' unless memo.empty? && segment.empty?
            next if segment.empty?

            next memo << encode_static(segment) unless segment.match?(HAS_DYNAMIC)

            tokens = segment.scan(DYNAMIC_TOKEN)
            next memo << encode_static(segment) if tokens.empty?

            names = tokens.map { |token| (token.length > 1) ? token[1..-1] : "param#{nameless_counter += 1}" }
            memo << "{#{names.join('+')}}"
          end

          result = "/#{result}" unless result.start_with?('/')
          result
        end
      end
    end
  end
end
