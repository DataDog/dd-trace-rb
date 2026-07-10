# frozen_string_literal: true

require 'cgi'

module Datadog
  module AppSec
    module Utils
      module HTTP
        # Module for parsing URL encoded payloads
        module URLEncoded
          # Matches Rack's default query bytesize limit, so parsing our own
          # payloads keeps the same guard against CPU/memory exhaustion.
          DEFAULT_BYTESIZE_LIMIT = 4 * 1024 * 1024

          AMPERSAND_BYTE = 0x26
          EQUALS_BYTE = 0x3D

          # Parses a URL encoded payload (query string or form data) into a hash
          # of keys and values, merging duplicate keys.
          #
          # Example:
          #
          #   URLEncoded.parse("foo=bar&foo=baz&qux=quux") # => {"foo" => ["bar", "baz"], "qux" => "quux"}
          #
          # Parsing stops once +limit+ bytes have been read, and the pair being
          # read at that point is discarded. This returns the pairs decoded so
          # far rather than raising or discarding the whole payload.
          def self.parse(payload, limit: DEFAULT_BYTESIZE_LIMIT)
            return {} if payload.nil? || payload.empty?

            result = {} #: Hash[::String, (::String | ::Array[::String?])?]
            segment_start = 0
            equals_index = -1
            index = 0
            limit_reached = false

            payload.each_byte do |byte|
              if index >= limit
                limit_reached = true
                break
              end

              case byte
              when AMPERSAND_BYTE
                set_param_value(result, payload, segment_start: segment_start, segment_end: index, equals_index: equals_index)
                segment_start = index + 1
                equals_index = -1
              when EQUALS_BYTE
                equals_index = index if equals_index == -1
              end

              index += 1
            end

            set_param_value(result, payload, segment_start: segment_start, segment_end: index, equals_index: equals_index) unless limit_reached

            result
          end

          def self.set_param_value(result, payload, segment_start:, segment_end:, equals_index:)
            if equals_index == -1
              key = payload.byteslice(segment_start, segment_end - segment_start) #: ::String
              value = nil
            else
              key = payload.byteslice(segment_start, equals_index - segment_start) #: ::String
              value = payload.byteslice(equals_index + 1, segment_end - equals_index - 1) #: ::String
            end

            return if key.empty? && value.nil?

            key = CGI.unescape(key)
            value = CGI.unescape(value) unless value.nil?

            case existing = result[key]
            when ::Array then existing.push(value)
            when nil then result[key] = value
            else result[key] = [existing, value]
            end
          end
          private_class_method :set_param_value
        end
      end
    end
  end
end
