# typed: false

require_relative 'assets'

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

      def self.negotiate(env)
        Response.new(status: 403,
                     headers: { 'Content-Type' => 'text/html' },
                     body: [Datadog::AppSec::Assets.blocked(format: format(env))])
      end

      private

      def self.format(env)
        format = env['HTTP_ACCEPT'] && env['HTTP_ACCEPT'].split(',').any? do |accept|
          if accept.start_with?('text/html')
            break :html
          elsif accept.start_with?('application/json')
            break :json
          end
        end

        format || :text
      end
    end
  end
end
