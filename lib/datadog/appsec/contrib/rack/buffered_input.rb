# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Wraps a `rack.input` stream with a buffer placed in front of it.
        # Every read drains the buffer first, then continues from the stream
        #
        # NOTE: Forward-only: no rewind, no seek
        #
        # NOTE: Rack 3 dropped the rewind requirement from the input stream contract
        # @see https://github.com/rack/rack/blob/v3.2.6/SPEC.rdoc
        class BufferedInput
          # NOTE: Rack's multipart parser reads in 1 MiB chunks, used to bound
          #       {#each} the same way
          # @see https://github.com/rack/rack/blob/v3.2.6/lib/rack/multipart/parser.rb#L54
          READ_BUFSIZE_BYTES = 1_048_576

          def initialize(stream, buffer:)
            @stream = stream
            @buffer = buffer
          end

          def read(length = nil, outbuf = nil)
            if length.nil?
              data = @buffer.read(nil, outbuf) || +''
              more = @stream.read

              data << more if more

              return data
            end

            data = @buffer.read(length, outbuf)

            if data.nil?
              more = @stream.read(length, outbuf)
              return more if more && !more.empty?

              # NOTE: Match `IO#read(length, outbuf)` at EOF. Return nil and clear
              #       the caller's buffer so stale bytes are not mistaken for data
              outbuf&.clear
              return
            end

            remaining = length - data.bytesize
            return data if remaining <= 0

            more = @stream.read(remaining)
            data << more if more

            data
          end

          def gets
            line = @buffer.gets

            return @stream.gets if line.nil?
            return line if line.end_with?("\n")

            more = @stream.gets
            more ? (line << more) : line
          end

          def each
            while (chunk = read(READ_BUFSIZE_BYTES))
              yield chunk
            end

            self
          end

          def close
            @buffer.close
          ensure
            @stream.close
          end
        end
      end
    end
  end
end
