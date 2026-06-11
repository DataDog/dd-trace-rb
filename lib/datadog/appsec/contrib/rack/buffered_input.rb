# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Rack
        # TODO: - refactor me
        # mention forward only
        class BufferedInput
          # NOTE: Reference here Rack value
          READ_CHUNK_SIZE = 1_048_576

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

              # NOTE: At EOF mirror `IO#read(length, buffer)` — return `nil`
              #       and empty the caller's output buffer so stale bytes aren't
              #       mistaken for data
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
            more ? (line + more) : line
          end

          def each
            while (chunk = read(READ_CHUNK_SIZE))
              yield chunk
            end

            self
          end

          def close
            @buffer.close
            @stream.close
          end
        end
      end
    end
  end
end
