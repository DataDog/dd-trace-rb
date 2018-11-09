require 'ddtrace/tracer'
require 'ddtrace/transport'
require 'ddtrace/transport/services'
require 'ddtrace/transport/traces'
require 'ddtrace/transport/http/client'

module Datadog
  module Transport
    module HTTP
      # Extension for HTTP::Client that adds backwards compatibility with the old writer API.
      # This should be removed when the writer is updated to use the Transport::HTTP:Client.
      module Compatibility
        attr_reader :response_callback

        def send(type, data)
          response = case type
                     when :services
                       deliver(Transport::Services::Parcel.new(data))
                     when :traces
                       deliver(Transport::Traces::Parcel.new(data))
                     else
                       Datadog::Tracer.log.error("Unsupported endpoint: #{endpoint}")
                       return nil
                     end

          response.code.tap do
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
            Transport::HTTP::Client::V4 => HTTPTransport::V4,
            Transport::HTTP::Client::V3 => HTTPTransport::V3,
            Transport::HTTP::Client::V2 => HTTPTransport::V2
          }.freeze
        end
      end
    end
  end
end
