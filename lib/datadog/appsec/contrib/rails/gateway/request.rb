# frozen_string_literal: true

require_relative '../../rack/input_peeker'
require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Gateway
          # Gateway Request argument. Normalized extration of data from ActionDispatch::Request
          class Request < Instrumentation::Gateway::Argument
            attr_reader :request

            def initialize(request)
              super()
              @request = request
            end

            def env
              request.env
            end

            def headers
              request.headers
            end

            def host
              request.host
            end

            def user_agent
              request.user_agent
            end

            def remote_addr
              request.remote_addr
            end

            def parsed_body
              # force body parameter parsing, which is done lazily by Rails
              request.parameters

              # usually Hash<String,String> but can be a more complex
              # Hash<String,String||Array||Hash> when e.g coming from JSON or
              # with Rails advanced param square bracket parsing
              body = request.env['action_dispatch.request.request_parameters']

              return if body.nil?
              return body unless request.env['action_dispatch.request.path_parameters']

              body.reject do |k, _v|
                request.env['action_dispatch.request.path_parameters'].key?(k)
              end
            end

            def route_params
              excluded = [:controller, :action]

              request.env.fetch('action_dispatch.request.path_parameters', {}).reject do |k, _v|
                excluded.include?(k)
              end
            end

            # Returns the request body size in bytes using all available methods,
            # or nil when the size cannot be measured within the limit
            #
            # NOTE: The priority of the measurement is the following:
            #       raw posted data, raw form vars, size if known, raw
            #       Content-Length, then buffering to the limit if unknown-length
            def body_bytesize(limit)
              raw_body = env['RAW_POST_DATA']
              return raw_body.bytesize if raw_body

              form_vars = env['rack.request.form_vars']
              return form_vars.bytesize if form_vars

              io = request.body
              return 0 unless io
              return io.size if io.respond_to?(:size)

              # NOTE: Read raw `CONTENT_LENGTH` as {ActionDispatch::Request#content_length}
              #       drains `rack.input` into `RAW_POST_DATA` on chunked Transfer-Encoding
              content_length = env['CONTENT_LENGTH']
              return content_length.to_i if content_length

              # NOTE: An already-read body (e.g. late-parsed multipart on Rack 3+) peeks
              #       as 0, so we skip byte_length but still collect the parsed body
              begin
                Rack::InputPeeker.peek_bytesize(env, limit: limit)
              rescue => e
                Datadog.logger.debug { "AppSec: Failed to measure Rails request body: #{e.class}: #{e.message}" }
                nil
              end
            end
          end
        end
      end
    end
  end
end
