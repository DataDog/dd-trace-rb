# frozen_string_literal: true

require 'uri'

require_relative '../../utils/http/media_type'
require_relative '../../utils/http/body'
require_relative '../../../core/utils/base64'
require_relative '../../../core/header_collection'
require_relative '../../../tracing/client_ip'

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        # Extracts WAF input addresses from normalized AWS Lambda API Gateway event payloads.
        # @api private
        module WAFAddresses
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
              'http.client_ip' => extract_client_ip(payload['source_ip'], headers),
              'server.request.method' => payload['method'],
              'server.request.body' => parse_body(payload, headers),
              'server.request.path_params' => payload['path_params']
            }

            data.compact!
            data
          end

          def from_response(payload)
            return {} if payload.nil? || payload.empty?

            headers = parse_headers(payload)
            data = {
              'server.response.status' => payload['statusCode']&.to_s,
              'server.response.headers' => headers,
              'server.response.headers.no_cookies' => headers.dup.tap { |h| h.delete('set-cookie') }
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

            body = Core::Utils::Base64.strict_decode64(body) if payload['base64_encoded']

            content_type = headers['content-type']
            return unless content_type

            media_type = AppSec::Utils::HTTP::MediaType.parse(content_type)
            return unless media_type

            AppSec::Utils::HTTP::Body.parse(body, media_type: media_type)
          end
        end
      end
    end
  end
end
