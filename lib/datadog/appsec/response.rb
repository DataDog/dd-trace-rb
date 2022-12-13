# typed: false

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

        def format(env)
          formats = ['text/html', 'application/json']
          accepted = env['HTTP_ACCEPT'].split(',').map { |m| Utils::HTTP::MediaRange.new(m) }.sort

          format = nil
          accepted.each do |range|
            # @type break: nil

            format = formats.find { |f| range === f }

            break if format
          end

          case format
          when 'text/html'
            :html
          when 'application/json'
            :json
          else
            :text
          end
        end
      end
    end
  end
end
