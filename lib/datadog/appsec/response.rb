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

          body = []
          body << content(content_type)

          Response.new(
            status: 403,
            headers: { 'Content-Type' => content_type },
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

        def content(content_type)
          content_format = CONTENT_TYPE_TO_FORMAT[content_type]

          using_default = Datadog.configuration.appsec.block.templates.using_default?(content_format)

          if using_default
            Datadog::AppSec::Assets.blocked(format: content_format)
          else
            Datadog.configuration.appsec.block.templates.send(content_format)
          end
        end
      end
    end
  end
end
