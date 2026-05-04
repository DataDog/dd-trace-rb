# frozen_string_literal: true

require 'uri'
require 'base64'

require_relative '../../utils/http/media_type'
require_relative '../../utils/http/body'
require_relative '../../../core/header_collection'
require_relative '../../../tracing/client_ip'

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        module WAFAddresses
          module_function

          def from_request(payload)
            headers = parse_headers(payload)
            source_ip = payload.dig('requestContext', 'identity', 'sourceIp') ||
              payload.dig('requestContext', 'http', 'sourceIp')

            data = {
              'server.request.cookies' => parse_cookies(headers),
              'server.request.query' => parse_query(payload),
              'server.request.uri.raw' => build_fullpath(payload),
              'server.request.headers' => headers,
              'server.request.headers.no_cookies' => headers.dup.tap { |h| h.delete('cookie') },
              'http.client_ip' => extract_client_ip(source_ip, headers),
              'server.request.method' => extract_method(payload),
              'server.request.body' => parse_body(payload, headers),
              'server.request.path_params' => payload['pathParameters'],
            }
            data.compact!
            data
          end

          def from_response(payload = {})
            payload ||= {}
            headers = parse_headers(payload)

            data = {
              'server.response.status' => payload['statusCode']&.to_s,
              'server.response.headers' => headers,
              'server.response.headers.no_cookies' => headers.dup.tap { |h| h.delete('set-cookie') },
            }
            data.compact!
            data
          end

          def parse_headers(payload)
            (payload['headers'] || {}).each_with_object({}) do |(key, value), hash|
              hash[key.downcase] = value
            end
          end

          def parse_cookies(headers)
            cookie_header = headers['cookie']
            return {} unless cookie_header

            cookie_header.split(';').each_with_object({}) do |pair, hash|
              name, value = pair.strip.split('=', 2)
              hash[name] = value if name
            end
          end

          def parse_query(payload)
            payload['multiValueQueryStringParameters'] ||
              payload['queryStringParameters'] ||
              {}
          end

          def build_fullpath(payload)
            path = payload['path'] || payload['rawPath']
            return unless path

            qs = build_query_string(payload)
            qs.empty? ? path : "#{path}?#{qs}"
          end

          def build_query_string(payload)
            raw = payload['rawQueryString']
            return raw if raw && !raw.empty?

            URI.encode_www_form(
              payload['multiValueQueryStringParameters'] ||
                payload['queryStringParameters'] ||
                {}
            )
          end

          def extract_method(payload)
            payload['httpMethod'] ||
              payload.dig('requestContext', 'http', 'method')
          end

          def extract_client_ip(remote_ip, headers)
            header_collection = Datadog::Core::HeaderCollection.from_hash(headers)
            Datadog::Tracing::ClientIp.extract_client_ip(header_collection, remote_ip)
          end

          def parse_body(payload, headers)
            body = payload['body']
            return unless body

            body = Base64.decode64(body) if payload['isBase64Encoded']

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
