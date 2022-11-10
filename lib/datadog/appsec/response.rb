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
        if env['HTTP_ACCEPT'] && env['HTTP_ACCEPT'].split(',').any? { |e| e.start_with?('text/html') }
          Response.new(status: 403, headers: { 'Content-Type' => 'text/html' }, body: [Datadog::AppSec::Assets.blocked(format: :html)])
        elsif env['HTTP_ACCEPT'] && env['HTTP_ACCEPT'].split(',').any? { |e| e.start_with?('application/json') }
          Response.new(status: 403, headers: { 'Content-Type' => 'application/json' }, body: [Datadog::AppSec::Assets.blocked(format: :json)])
        else
          Response.new(status: 403, headers: { 'Content-Type' => 'text/plain' }, body: [Datadog::AppSec::Assets.blocked(format: :text)])
        end
      end
    end
  end
end
