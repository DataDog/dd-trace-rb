require 'ddtrace/tracer'
require 'ddtrace/transport'
require 'ddtrace/transport/request'
require 'ddtrace/transport/traces'
require 'ddtrace/transport/http/api'

module Datadog
  module Transport
    module HTTP
      # Extension for HTTP::Client that adds backwards compatibility with the old writer API.
      # This should be removed when the writer is updated to use the Transport::HTTP:Client.
      module Compatibility
        attr_reader :response_callback

        def send(type, data)
          # Wrap the data in a parcel
          unless data.is_a?(Transport::Parcel)
            data = case type
                   when :traces
                     Transport::Traces::Parcel.new(data)
                   else
                     Datadog::Tracer.log.error("Unsupported transport data type: #{type}")
                     return nil
                   end
          end

          # Deliver the request
          request = Transport::Request.new(type, data)
          response = deliver(request)

          response.code.tap do
            # TODO: Update returned "response", such that its compatible with the writer
            #       Adapters may return responses that are not Net::HTTP responses, where the writer expects them.
            #       Need to make sure the response types are compatible with the callback.
            response_callback.call(type, response, api_compatibility_mapping[active_api]) unless response_callback.nil?
          end
        end

        def server_error?(code)
          code.between?(500, 599)
        end

        def stats
          {}
        end

        private

        def api_compatibility_mapping
          @api_compatibility_mapping ||= {
            Transport::HTTP::API::V4 => HTTPTransport::V4,
            Transport::HTTP::API::V3 => HTTPTransport::V3,
            Transport::HTTP::API::V2 => HTTPTransport::V2
          }.freeze
        end
      end
    end
  end
end
