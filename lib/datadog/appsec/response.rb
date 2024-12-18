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
        def negotiate(env, actions)
          # @type var configured_response: Response?
          configured_response = nil
          actions.each do |type, parameters|
            # Need to use next to make steep happy :(
            # I rather use break to stop the execution
            next if configured_response

            configured_response = case type
                                  when 'block_request'
                                    block_response(env, parameters)
                                  when 'redirect_request'
                                    redirect_response(env, parameters)
                                  end
          end

          configured_response || default_response(env)
        end

        def graphql_response(gateway_multiplex)
          multiplex_return = []
          gateway_multiplex.queries.each do |query|
            # This method is only called in places where GraphQL-Ruby is already required
            query_result = ::GraphQL::Query::Result.new(
              query: query,
              values: JSON.parse(content('application/json'))
            )
            multiplex_return << query_result
          end

          multiplex_return
        end

        private

        def default_response(env)
          content_type = content_type(env)

          body = []
          body << content(content_type)

          Response.new(
            status: 403,
            headers: { 'Content-Type' => content_type },
            body: body,
          )
        end

        def block_response(env, options)
          content_type = if options['type'] == 'auto'
                           content_type(env)
                         else
                           FORMAT_TO_CONTENT_TYPE[options['type']]
                         end

          body = []
          body << content(content_type)

          Response.new(
            status: options['status_code']&.to_i || 403,
            headers: { 'Content-Type' => content_type },
            body: body,
          )
        end

        def redirect_response(env, options)
          if options['location'] && !options['location'].empty?
            content_type = content_type(env)

            headers = {
              'Content-Type' => content_type,
              'Location' => options['location']
            }

            status_code = options['status_code'].to_i
            Response.new(
              status: (status_code >= 300 && status_code < 400 ? status_code : 303),
              headers: headers,
              body: [],
            )
          else
            default_response(env)
          end
        end

        CONTENT_TYPE_TO_FORMAT = {
          'application/json' => :json,
          'text/html' => :html,
          'text/plain' => :text,
        }.freeze

        FORMAT_TO_CONTENT_TYPE = {
          'json' => 'application/json',
          'html' => 'text/html',
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
