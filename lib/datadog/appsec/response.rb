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
        format = if accepted?('text/html', env)
                   :html
                 elsif accepted?('application/json', env)
                   :json
                 else
                   :text
                 end

        Response.new(status: 403,
                     headers: { 'Content-Type' => 'text/html' },
                     body: [Datadog::AppSec::Assets.blocked(format: format)])
      end

      private

      def self.accepted?(mime, env)
        env['HTTP_ACCEPT'] && env['HTTP_ACCEPT'].split(',').any? { |e| e.start_with?(mime) }
      end
    end
  end
end
