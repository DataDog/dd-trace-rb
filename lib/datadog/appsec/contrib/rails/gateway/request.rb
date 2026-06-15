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
            BodyMeasurement = Struct.new(:byte_length, :collect_body)

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

            # Measures the request body size in bytes and decides whether the body
            # may be collected, decoupling the two because the Rails watcher runs
            # in the controller, after Rails has already parsed the body
            #
            # NOTE: The priority of the measurement is the following:
            #       raw posted data, raw form vars, size if known, raw
            #       Content-Length, then buffering to the limit if unknown-length.
            #       When the size is unrecoverable but the body was already parsed,
            #       the parsed body is still collected without a byte length.
            def measure_body(limit)
              return BodyMeasurement.new(nil, false) if limit.zero?

              raw_body = env['RAW_POST_DATA']
              if raw_body
                byte_length = raw_body.bytesize
                return BodyMeasurement.new(byte_length, byte_length <= limit)
              end

              form_vars = env['rack.request.form_vars']
              if form_vars
                byte_length = form_vars.bytesize
                return BodyMeasurement.new(byte_length, byte_length <= limit)
              end

              io = request.body
              return BodyMeasurement.new(0, false) unless io

              if io.respond_to?(:size)
                byte_length = io.size
                return BodyMeasurement.new(byte_length, byte_length <= limit)
              end

              content_length = env['CONTENT_LENGTH']
              if content_length
                byte_length = content_length.to_i
                return BodyMeasurement.new(byte_length, byte_length <= limit)
              end

              return BodyMeasurement.new(nil, true) if body_parameters_parsed? && !self.class.rewind_rack_input?

              byte_length = measure_body!(io, limit: limit)
              BodyMeasurement.new(byte_length, !byte_length.nil?)
            end

            private

            def body_parameters_parsed?
              env.key?('action_dispatch.request.request_parameters')
            end

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
              buffer = +''
              max = limit + 1

              while buffer.bytesize <= limit
                chunk = io.read(max - buffer.bytesize)
                break if chunk.nil? || chunk.empty?

                buffer << chunk
              end

              over_limit = buffer.bytesize > limit

              if self.class.rewind_rack_input? && io.respond_to?(:rewind)
                io.rewind
              elsif over_limit
                env['rack.input'] = Rack::BufferedInput.new(io, buffer: StringIO.new(buffer))
              else
                env['rack.input'] = StringIO.new(buffer)
              end

              over_limit ? nil : buffer.bytesize
            end
          end
        end
      end
    end
  end
end
