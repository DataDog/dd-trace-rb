# frozen_string_literal: true

require 'cgi'

module Datadog
  module AppSec
    module Utils
      module HTTP
        # Module for parsing URL encoded payloads
        module URLEncoded
          # Parses a URL encoded payload (query string or form data) into a hash
          # of keys and values, merging duplicate keys.
          #
          # Example:
          #
          #   URLEncoded.parse("foo=bar&foo=baz&qux=quux") # => {"foo" => ["bar", "baz"], "qux" => "quux"}
          #
          # NOTE: Use it in the absence of `Rack::Utils.parse_query`
          #
          # WARNING: This method doesn't limit params byte size.
          #          See: https://github.com/rack/rack/blob/603b799de38b5eb9b2ff1657c8036a20f4c4db7b/lib/rack/query_parser.rb#L231-L233
          def self.parse(payload)
            return {} if payload.nil? || payload.empty?

            payload.split('&').each_with_object({}) do |pair, memo|
              next if pair.empty?

              # NOTE: Steep has issues with mutation methods
              #       See https://github.com/ruby/rbs/issues/2819
              #
              # @type var key: ::String
              # @type var value: ::String
              key, value = pair.split('=', 2).map! do |value| #: ::String
                CGI.unescape(value)
              end

              if (stored = memo[key])
                if stored.is_a?(Array)
                  stored.push(value)
                else
                  memo[key] = [stored, value]
                end
              else
                memo[key] = value
              end
            end
          end
        end
      end
    end
  end
end
