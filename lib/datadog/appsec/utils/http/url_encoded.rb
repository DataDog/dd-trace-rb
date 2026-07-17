# frozen_string_literal: true

require 'cgi'

module Datadog
  module AppSec
    module Utils
      module HTTP
        # Module for parsing URL encoded payloads
        module URLEncoded
          module_function

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
          def parse(payload, limit: DEFAULT_BYTESIZE_LIMIT)
            raise ArgumentError, 'limit must not be negative' if limit < 0

            return {} if payload.nil? || payload.empty? || limit.zero?

            # @type var result: URLEncoded::params
            result = {}
            payload_bytesize = payload.bytesize
            bytes_to_parse = (payload_bytesize < limit) ? payload_bytesize : limit

            index = 0
            param_start = 0
            equals_index = nil # : Integer?

            payload.each_byte do |byte|
              break if index >= bytes_to_parse

              if byte == AMPERSAND_BYTE
                param_end = index

                if equals_index
                  key = payload.byteslice(param_start, equals_index - param_start) # : String
                  value = payload.byteslice(equals_index + 1, param_end - equals_index - 1) # : String?
                else
                  key = payload.byteslice(param_start, param_end - param_start) # : String
                  value = nil
                end

                if !key.empty? || value
                  key = CGI.unescape(key)
                  value = CGI.unescape(value) if value

                  add_param(result, key, value)
                end

                param_start = index + 1
                equals_index = nil
              elsif byte == EQUALS_BYTE
                equals_index ||= index
              end

              index += 1
            end

            if bytes_to_parse == payload_bytesize && param_start < index
              param_end = index

              if equals_index
                key = payload.byteslice(param_start, equals_index - param_start) # : String
                value = payload.byteslice(equals_index + 1, param_end - equals_index - 1) # : String?
              else
                key = payload.byteslice(param_start, param_end - param_start) # : String
                value = nil
              end

              if !key.empty? || value
                key = CGI.unescape(key)
                value = CGI.unescape(value) if value

                add_param(result, key, value)
              end
            end

            result
          end

          private_class_method def add_param(params, key, value)
            case existing = params[key]
            when ::Array then existing.push(value)
            when nil then params[key] = value
            else params[key] = [existing, value]
            end
          end
        end
      end
    end
  end
end
