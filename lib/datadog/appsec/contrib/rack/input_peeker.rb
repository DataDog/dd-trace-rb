# frozen_string_literal: true

require 'stringio'
require_relative 'buffered_input'

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Peeks at `rack.input` without changing what downstream Rack code can read
        #
        # @api private
        module InputPeeker
          module_function

          # Peeks at `env['rack.input']` and returns the body bytesize when it
          # can be measured within the given limit
          #
          # NOTE: Over-limit bodies cannot be fully measured, so returning `nil`
          #       is the tradeoff we accept
          #
          # WARNING: For forward-only input, replaces `env['rack.input']` with a
          #          replay stream over the peeked bytes, preserving the rest
          #          of the original stream
          #
          # @param env [Hash] Rack environment
          # @param limit [Integer] Maximum body bytesize to measure
          # @return [Integer, nil] `Integer` bytesize when measured within
          #   `limit`, including `0`; `nil` when input is missing, over the
          #   limit, or cannot be preserved for downstream reads
          def peek_bytesize(env, limit:)
            rack_input = env['rack.input']
            return unless rack_input

            rewindable = rewind? && rack_input.respond_to?(:rewind)

            # NOTE: Rack 2 requires `rack.input` to be rewindable. Rewind before peeking
            #       in case an upstream framework already consumed part of the stream
            return if rewindable && !rewind(rack_input)

            buffer = peek(rack_input, limit)
            over_limit = buffer.bytesize > limit

            if rewindable
              # NOTE: If we cannot rewind after peeking, downstream code would observe
              #       a partially consumed body. Treat it as not safely collectable
              return unless rewind(rack_input)
            else
              env['rack.input'] = if over_limit
                BufferedInput.new(rack_input, buffer: StringIO.new(buffer))
              else
                StringIO.new(buffer)
              end
            end

            over_limit ? nil : buffer.bytesize
          end

          private_class_method def rewind?
            return @rewind if defined?(@rewind)

            @rewind = ::Gem::Version.new(::Rack.release) < ::Gem::Version.new('3')
          end

          private_class_method def rewind(io)
            io.rewind
            true
          rescue => e
            Datadog.logger.debug { "AppSec: Failed to rewind `rack.input`: #{e.class}: #{e.message}" }
            false
          end

          private_class_method def peek(io, limit)
            # NOTE: Read one byte past the limit to distinguish an exact-limit body
            #       from an over-limit body without reading the whole stream.
            max = limit + 1
            buffer = +''.b

            while buffer.bytesize <= limit
              chunk = io.read(max - buffer.bytesize)
              break if chunk.nil? || chunk.empty?

              buffer << chunk
            end

            buffer
          end
        end
      end
    end
  end
end
