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
          response = if block_given?
                       yield(out, request)
                     else
                       send_default_request(out, request)
                     end

          # Update statistics
          update_stats_from_response!(response)

          # Return response
          response
        rescue StandardError => e
          message = "Internal error during IO transport request. Cause: #{e.message} Location: #{e.backtrace.first}"

          # Log error
          if stats.consecutive_errors > 0
            Datadog.logger.debug(message)
          else
            Datadog.logger.error(message)
          end

          # Update statistics
          update_stats_from_exception!(e)

          InternalErrorResponse.new(e)
        end

        protected

        def encode_data(encoder, request)
          request.parcel.encode_with(encoder)
        end

        def write_data(out, data)
          out.puts(data)
        end

        private

        def send_default_request(out, request)
          # Encode data
          data = encode_data(encoder, request)

          # Write to IO
          result = write_data(out, data)

          # Generate a response
          IO::Response.new(result)
        end
      end
    end
  end
end
