# frozen_string_literal: true

require_relative '../../../instrumentation/gateway/argument'
require_relative '../../../../core/header_collection'
require_relative '../../../../tracing/client_ip'

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        module Gateway
          class Request < Instrumentation::Gateway::Argument
            attr_reader :event

            def initialize(event)
              super()
              @event = event
            end

            def headers
              @headers ||= (event['headers'] || {}).each_with_object({}) do |(key, value), hash|
                hash[key.downcase] = value
              end
            end

            def cookies
              @cookies ||= parse_cookies
            end

            def query
              @query ||= event['multiValueQueryStringParameters'] ||
                event['queryStringParameters'] ||
                {}
            end

            def fullpath
              @fullpath ||= begin
                path = request_path
                qs = query_string
                qs.empty? ? path : "#{path}?#{qs}"
              end
            end

            def method
              @method ||= event['httpMethod'] ||
                event.dig('requestContext', 'http', 'method') ||
                'GET'
            end

            def client_ip
              @client_ip ||= begin
                remote_ip = source_ip
                header_collection = Datadog::Core::HeaderCollection.from_hash(headers)
                Datadog::Tracing::ClientIp.extract_client_ip(header_collection, remote_ip)
              end
            end

            def body
              @body ||= begin
                raw = event['body']
                return nil if raw.nil?

                event['isBase64Encoded'] ? Base64.decode64(raw) : raw
              end
            end

            def path_parameters
              event['pathParameters']
            end

            def host
              headers['host']
            end

            def user_agent
              headers['user-agent']
            end

            def remote_addr
              source_ip
            end

            def form_hash
              return nil unless body

              content_type = headers['content-type']
              return nil unless content_type

              if content_type.include?('application/x-www-form-urlencoded')
                URI.decode_www_form(body).to_h
              elsif content_type.include?('application/json')
                JSON.parse(body)
              end
            rescue => _e
              nil
            end

            private

            def request_path
              event['path'] || event['rawPath'] || '/'
            end

            def query_string
              raw = event['rawQueryString']
              return raw if raw && !raw.empty?

              params = event['queryStringParameters']
              return '' unless params

              params.map { |key, value| "#{key}=#{value}" }.join('&')
            end

            def source_ip
              event.dig('requestContext', 'identity', 'sourceIp') ||
                event.dig('requestContext', 'http', 'sourceIp')
            end

            def parse_cookies
              cookie_header = headers['cookie']
              return {} unless cookie_header

              cookie_header.split(';').each_with_object({}) do |pair, hash|
                name, value = pair.strip.split('=', 2)
                hash[name] = value if name
              end
            end
          end
        end
      end
    end
  end
end
