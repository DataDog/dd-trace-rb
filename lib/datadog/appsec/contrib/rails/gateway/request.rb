# frozen_string_literal: true

require 'stringio'

require_relative '../../rack/buffered_input'
require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Gateway
          # Gateway Request argument. Normalized extration of data from ActionDispatch::Request
          class Request < Instrumentation::Gateway::Argument
            def self.rewind_rack_input?
              return @rewind_rack_input if defined?(@rewind_rack_input)

              @rewind_rack_input = Gem::Version.new(::Rack.release) < Gem::Version.new('3')
            end

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

              body.reject do |k, _v|
                request.env['action_dispatch.request.path_parameters'].key?(k)
              end
            end

            def route_params
              excluded = [:controller, :action]

              request.env['action_dispatch.request.path_parameters'].reject do |k, _v|
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
              #       as 0, so we skip byte_length but still collect the parsed body.
              measure_body!(io, limit: limit)
            end

            private

            # Peeks the body up to limit + 1 bytes to measure its size without parsing,
            # then restores `rack.input` for downstream reads
            #
            # NOTE: Rack 2 requires `rack.input` to stay rewindable.
            #
            # NOTE: Rack 3+ rewind contract is unreliable. Falcon's `rewind`
            #       returns `true` without repositioning. We always replace
            #       `rack.input` with a replay over the bytes already read:
            #       {Rack::BufferedInput} over the limit, {StringIO} otherwise.
            #
            # Returns the byte size within the limit, or `nil` when over it.
            def measure_body!(io, limit:)
              rewindable = self.class.rewind_rack_input? && io.respond_to?(:rewind)

              # NOTE: Rails runs in the controller, so the input may already be at EOF.
              #       Rewind first to measure from the start; bail out if it refuses.
              io.rewind if rewindable

              buffer = +''
              max = limit + 1

              while buffer.bytesize <= limit
                chunk = io.read(max - buffer.bytesize)
                break if chunk.nil? || chunk.empty?

                buffer << chunk
              end

              over_limit = buffer.bytesize > limit

              if rewindable
                io.rewind
              elsif over_limit
                env['rack.input'] = Rack::BufferedInput.new(io, buffer: StringIO.new(buffer))
              else
                env['rack.input'] = StringIO.new(buffer)
              end

              over_limit ? nil : buffer.bytesize
            rescue => e
              Datadog.logger.debug { "AppSec: Failed to measure Rails request body: #{e.class}: #{e.message}" }
            end
          end
        end
      end
    end
  end
end
