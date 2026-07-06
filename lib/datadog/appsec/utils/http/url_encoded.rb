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
          BYTESIZE_LIMIT = 4 * 1024 * 1024

          # Parses a URL encoded payload (query string or form data) into a hash
          # of keys and values, merging duplicate keys.
          #
          # Example:
          #
          #   URLEncoded.parse("foo=bar&foo=baz&qux=quux") # => {"foo" => ["bar", "baz"], "qux" => "quux"}
          #
          # Parsing stops once +bytesize_limit+ bytes have been read, and the
          # pair being read at that point is discarded. This returns the pairs
          # decoded so far rather than raising or discarding the whole payload.
          def self.parse(payload, bytesize_limit: BYTESIZE_LIMIT)
            return {} if payload.nil? || payload.empty?

            result = {} #: Hash[::String, (::String | ::Array[::String?])?]
            key = nil #: ::String?
            value = +''
            consumed = 0
            truncated = false

            payload.each_char do |char|
              consumed += char.bytesize
              if consumed > bytesize_limit
                truncated = true
                break
              end

              case char
              when '&'
                set_param_value(result, key, value)
                key = nil
                value = +''
              when '='
                if key
                  value << char
                else
                  key = value
                  value = +''
                end
              else
                value << char
              end
            end

            set_param_value(result, key, value) unless truncated

            result
          end

          def self.set_param_value(result, key, value)
            return if key.nil? && value.empty?

            decoded_key = CGI.unescape(key || value)
            decoded_value = key.nil? ? nil : CGI.unescape(value) #: ::String?

            case existing = result[decoded_key]
            when ::Array then existing.push(decoded_value)
            when nil then result[decoded_key] = decoded_value
            else result[decoded_key] = [existing, decoded_value]
            end
          end
          private_class_method :set_param_value
        end
      end
    end
  end
end
