# frozen_string_literal: true

require_relative '../statistics'
require_relative 'response'

module Datadog
  module Tracing
    module Transport
      module IO
        # Encodes and writes tracer data to IO
        class Client
          include Transport::Statistics

          attr_reader \
            :encoder,
            :out

          def initialize(out, encoder, options = {})
            @out = out
            @encoder = encoder

            # Note: The :encode option was previously supported but is no longer used.
            # Data is now expected to be pre-encoded in the Parcel before reaching this client,
            # matching the behavior of other transports (e.g., HTTP transport).
            # If provided, the :encode option will be silently ignored for backwards compatibility.
            @request_block = options.fetch(:request, method(:send_default_request))
            @write_block = options.fetch(:write, method(:write_data))
            @response_block = options.fetch(:response, method(:build_response))
          end

          def send_request(request)
            # Write data to IO
            # If block is given, allow it to handle writing
            # Otherwise do a standard encode/write/response.
            response = if block_given?
              yield(out, request)
            else
              @request_block.call(out, request)
            end

            # Update statistics
            update_stats_from_response!(response)

            # Return response
            response
          rescue => e
            message =
              "Internal error during IO transport request. Cause: #{e.class.name}: #{e.message} " \
                "Location: #{Array(e.backtrace).first}"

            # Log error
            if stats.consecutive_errors > 0
              Datadog.logger.debug(message)
            else
              # Not to report telemetry logs
              Datadog.logger.error(message)
            end

            # Update statistics
            update_stats_from_exception!(e)

            InternalErrorResponse.new(e)
          end

          def write_data(out, data)
            out.puts(data)
          end

          def build_response(_request, _data, result)
            IO::Response.new(result)
          end

          private

          def send_default_request(out, request)
            # Get already-encoded data from parcel
            data = request.parcel.data

            # Write to IO
            result = @write_block.call(out, data)

            # Generate a response
            @response_block.call(request, data, result)
          end
        end
      end
    end
  end
end
