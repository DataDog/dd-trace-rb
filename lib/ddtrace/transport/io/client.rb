require 'ddtrace/transport/statistics'
require 'ddtrace/transport/io/response'

module Datadog
  module Transport
    module IO
      # Encodes and writes tracer data to IO
      class Client
        include Transport::Statistics

        attr_reader \
          :encoder,
          :out

        def initialize(out, encoder)
          @out = out
          @encoder = encoder
        end

        def send_request(request)
          # Write data to IO
          # If block is given, allow it to handle writing
          # Otherwise use default encoding.
          response = block_given? ? yield(out, request) : send_default_request(out, request)

          # Update statistics
          update_stats_from_response!(response)

          # Return response
          response
        rescue StandardError => e
          message = "Internal error during IO transport request. Cause: #{e.message} Location: #{e.backtrace.first}"

          # Log error
          if stats.consecutive_errors > 0
            Datadog::Logger.log.debug(message)
          else
            Datadog::Logger.log.error(message)
          end

          # Update statistics
          update_stats_from_exception!(e)

          InternalErrorResponse.new(e)
        end

        private

        def send_default_request(out, request)
          # Encode data
          encoded_data = encoder.encode(request.parcel.data)

          # Write to IO
          bytes_written = out.write(encoded_data)

          # Generate a response
          IO::Response.new(bytes_written)
        end
      end
    end
  end
end
