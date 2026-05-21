# frozen_string_literal: true

module Datadog
  module AppSec
    module RouteNormalizer
      module StringRoute
        DYNAMIC_TOKEN = /:\w+|(?<!\w)\*\w*/
        HAS_DYNAMIC = /[:\*]/
        ENCODE_PATTERN = /[^A-Za-z0-9.\-~_\/]/

        module_function

        def encode_static(text)
          return text unless text.match?(ENCODE_PATTERN)
          text.gsub(ENCODE_PATTERN) { |c| c.bytes.map { |b| "%%%02X" % b }.join }
        end

        def normalize(route_pattern)
          nameless_counter = 0
          route = route_pattern.delete('()?')

          result = route.split('/', -1).each_with_object(+"") do |segment, memo|
            memo << '/' unless memo.empty? && segment.empty?
            next if segment.empty?

            unless segment.match?(HAS_DYNAMIC)
              memo << encode_static(segment)
              next
            end

            tokens = segment.scan(DYNAMIC_TOKEN)
            if tokens.empty?
              memo << encode_static(segment)
              next
            end

            names = tokens.map { |token|
              (token.length > 1) ? token[1..-1] : "param#{nameless_counter += 1}"
            }
            memo << "{#{names.join('+')}}"
          end

          result = "/#{result}" unless result.start_with?('/')
          result
        end
      end
    end
  end
end
