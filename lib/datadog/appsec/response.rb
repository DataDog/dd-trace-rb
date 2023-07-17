# frozen_string_literal: true

require_relative 'assets'
require_relative 'utils/http/media_range'

module Datadog
  module AppSec
    # AppSec response
    class Response
      attr_reader :status, :headers, :body

      def initialize(status:, headers: {}, body: [])
        @status = status
        @headers = headers
        @body = body
      end

      def to_rack
        [status, headers, body]
      end

      def to_sinatra_response
        ::Sinatra::Response.new(body, status, headers)
      end

      def to_action_dispatch_response
        ::ActionDispatch::Response.new(status, headers, body)
      end

      class << self
        def negotiate(env)
          content_type = content_type(env)

          Datadog.logger.debug { "negotiated response content type: #{content_type}" }

          headers = { 'Content-Type' => content_type }
          headers['Location'] = location.to_s if redirect?

          body = []
          body << content(content_type) unless redirect?

          Response.new(
            status: status,
            headers: headers,
            body: body,
          )
        end

        private

        CONTENT_TYPE_TO_FORMAT = {
          'application/json' => :json,
          'text/html' => :html,
          'text/plain' => :text,
        }.freeze

        DEFAULT_CONTENT_TYPE = 'application/json'
        REDIRECT_STATUS = [301, 302, 303, 307, 308].freeze

        def content_type(env)
          return DEFAULT_CONTENT_TYPE unless env.key?('HTTP_ACCEPT')

          accept_types = env['HTTP_ACCEPT'].split(',').map(&:strip)

          accepted = accept_types.map { |m| Utils::HTTP::MediaRange.new(m) }.sort!.reverse!

          accepted.each do |range|
            type_match = CONTENT_TYPE_TO_FORMAT.keys.find { |type| range === type }

            return type_match if type_match
          end

          DEFAULT_CONTENT_TYPE
        rescue Datadog::AppSec::Utils::HTTP::MediaRange::ParseError
          DEFAULT_CONTENT_TYPE
        end

        def status
          Datadog.configuration.appsec.block.status
        end

        def redirect?
          REDIRECT_STATUS.include?(status)
        end

        def location
          Datadog.configuration.appsec.block.location
        end

        def content(content_type)
          setting = Datadog.configuration.appsec.block.templates[content_type]

          case setting
          when :html, :json, :text
            Datadog::AppSec::Assets.blocked(format: setting)
          when String, Pathname
            path = setting.to_s

            cache[path] ||= (File.open(path, 'rb', &:read) || '')
          else
            raise ArgumentError, "unexpected type: #{content_type.inspect}"
          end
        end

        def cache
          @cache ||= {}
        end
      end
    end
  end
end
