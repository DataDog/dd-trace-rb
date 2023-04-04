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
          Response.new(
            status: 403,
            headers: { 'Content-Type' => 'text/html' },
            body: [Datadog::AppSec::Assets.blocked(format: format(env))]
          )
        end

        private

        FORMAT_MAP = {
          'text/html' => :html,
          'application/json' => :json,
          'text/plain' => :text,
        }.freeze

        DEFAULT_FORMAT = :text

        def format(env)
          return DEFAULT_FORMAT unless env.key?('HTTP_ACCEPT')

          accepted = env['HTTP_ACCEPT'].split(',').map { |m| Utils::HTTP::MediaRange.new(m) }.sort

          accepted.each_with_object(DEFAULT_FORMAT) do |_default, range|
            format = FORMAT_MAP.keys.find { |type, _format| range === type }

            return FORMAT_MAP[format] if format
          end
        end
      end
    end
  end
end
