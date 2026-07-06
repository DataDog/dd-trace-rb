# frozen_string_literal: true

require 'uri'

require_relative '../../utils/http/media_type'
require_relative '../../utils/http/body'
require_relative '../../../core/utils/base64_codec'
require_relative '../../../core/header_collection'
require_relative '../../../tracing/client_ip'

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        # Extracts WAF input addresses from normalized AWS Lambda API Gateway event payloads.
        # @api private
        module WAFAddresses
          BASE64_CHARS_PER_GROUP = 4
          BASE64_BYTES_PER_GROUP = 3
          BASE64_PADDING_BYTE = "=".ord

          module_function

          def from_request(payload)
            return {} if payload.nil? || payload.empty?

            headers = parse_headers(payload)
            data = {
              'server.request.cookies' => parse_cookies(payload, headers),
              'server.request.query' => payload['query'],
              'server.request.uri.raw' => build_fullpath(payload),
              'server.request.headers' => headers,
              'server.request.headers.no_cookies' => headers.dup.tap { |h| h.delete('cookie') },
              'server.request.method' => payload['method'],
              'server.request.body' => parse_body(payload, headers),
              'server.request.body.byte_length' => body_byte_length(payload),
              'server.request.path_params' => payload['path_params'],
              'http.client_ip' => extract_client_ip(payload['source_ip'], headers)
            }

            data.compact!
            data
          end

          def from_response(payload)
            return {} if payload.nil? || payload.empty?

            headers = parse_headers(payload)
            data = {
              'server.response.status' => payload['status_code']&.to_s,
              'server.response.headers' => headers,
              'server.response.headers.no_cookies' => headers.dup.tap { |h| h.delete('set-cookie') },
              'server.response.body' => parse_body(payload, headers),
              'server.response.body.byte_length' => body_byte_length(payload)
            }

            data.compact!
            data
          end

          def parse_headers(payload)
            (payload['headers'] || {}).each_with_object({}) do |(key, value), hash|
              hash[key.downcase] = value
            end
          end

          def parse_cookies(payload, headers)
            raw_pairs = payload['cookies'] || headers['cookie']&.split(';')
            return unless raw_pairs

            raw_pairs.each_with_object({}) do |pair, hash|
              name, value = pair.strip.split('=', 2)
              hash[name] = value if name
            end
          end

          def build_fullpath(payload)
            path = payload['path']
            return unless path

            query_string = build_query_string(payload)
            query_string ? "#{path}?#{query_string}" : path
          end

          def build_query_string(payload)
            query_string = payload['query_string']
            return query_string if query_string && !query_string.empty?

            query = payload['query']
            return if query.nil? || query.empty?

            URI.encode_www_form(query)
          end

          def extract_client_ip(remote_ip, headers)
            header_collection = Datadog::Core::HeaderCollection.from_hash(headers)
            Datadog::Tracing::ClientIp.extract_client_ip(header_collection, remote_ip)
          end

          def parse_body(payload, headers)
            body = payload['body']
            return unless body

            if (byte_length = body_byte_length(payload))
              return if byte_length > Datadog.configuration.appsec.body_parsing_size_limit
            end

            content_type = headers['content-type']
            return unless content_type

            media_type = AppSec::Utils::HTTP::MediaType.parse(content_type)
            return unless media_type

            body = Core::Utils::Base64Codec.strict_decode64(body) if payload['base64_encoded']
            AppSec::Utils::HTTP::Body.parse(
              body, media_type: media_type, bytesize_limit: Datadog.configuration.appsec.body_parsing_size_limit
            )
          rescue ArgumentError => e
            AppSec.telemetry.report(e, description: 'AppSec: Failed to decode base64 body')

            nil
          end

          def body_byte_length(payload)
            body = payload['body']

            return unless body
            return body.bytesize unless payload['base64_encoded']

            # NOTE: Base64 packs every 3 bytes into 4 characters and pads the last
            #       group with up to two "=" bytes. The decoded length is therefore
            #       derivable from the encoded length, letting us measure the raw
            #       body size without allocating the decoded string.
            padding = 0
            if body.getbyte(-1) == BASE64_PADDING_BYTE
              padding = 1
              padding = 2 if body.getbyte(-2) == BASE64_PADDING_BYTE
            end

            body.bytesize / BASE64_CHARS_PER_GROUP * BASE64_BYTES_PER_GROUP - padding
          end
        end
      end
    end
  end
end
