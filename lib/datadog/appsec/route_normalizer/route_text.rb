# frozen_string_literal: true

module Datadog
  module AppSec
    module RouteNormalizer
      # Percent-encodes route text, leaving param templates untouched
      #
      # @api private
      module RouteText
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

        # Escapes literal route text into normalized-route form
        #
        # Example:
        #
        #  a+b => a%2Bb
        #  café => caf%C3%A9
        #  /users/path => /users/path
        #
        # NOTE: {URI::Parser#escape} with {DISALLOWED_CHARS} gives the same output,
        #       but the generic gsub/sprintf path is slower and allocates more per request
        def escape(text)
          return text unless text.match?(DISALLOWED_CHARS)

          buffer = String.new(capacity: text.bytesize * MAX_ENCODED_BYTE_SIZE, encoding: Encoding::UTF_8)
          text.each_byte { |byte| buffer << BYTE_ENCODING_TABLE.fetch(byte) }
          buffer
        # NOTE: Defensive only — this can never happen. {String#each_byte} yields
        #       integers in 0-255 and {BYTE_ENCODING_TABLE} has an entry for every one
        rescue IndexError => e
          AppSec.telemetry&.report(e, description: 'AppSec: Route text byte outside 0-255 escape table')
          '~invalid~'
        end
      end
    end
  end
end
