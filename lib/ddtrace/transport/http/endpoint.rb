require 'net/http'
require 'ddtrace/transport/http/response'

module Datadog
  module Transport
    module HTTP
      # Generic endpoint receives POST data
      class PostEndpoint
        attr_reader \
          :path

        def initialize(path, options = {})
          @path = path
        end

        def deliver(service, data, options = {})
          post = Net::HTTP::Post.new(path, options[:headers])
          post.body = data

          # Connect and send the request
          http_response = service.open do |http|
            http.request(post)
          end

          # Build and return response
          HTTP::Response.new(http_response)
        end
      end

      # Endpoint that receives encoded parcels
      class ParcelEndpoint < PostEndpoint
        HEADER_CONTENT_TYPE = 'Content-Type'.freeze

        attr_reader :encoder

        def initialize(path, encoder, options = {})
          super(path, options)
          @encoder = encoder
        end

        def deliver(service, parcel, options)
          # Encode body
          options[:encoder] ||= encoder
          data = parcel.encode_with(options[:encoder])

          # Add content type header
          options[:headers] ||= {}
          options[:headers][HEADER_CONTENT_TYPE] = options[:encoder].content_type

          super(service, data, options)
        end
      end

      # Endpoint that receives Traces::Parcel
      class TracesEndpoint < ParcelEndpoint
        HEADER_TRACE_COUNT = 'X-Datadog-Trace-Count'.freeze

        def deliver(service, parcel, options)
          options[:headers] ||= {}
          options[:headers][HEADER_TRACE_COUNT] = parcel.count.to_s
          super(service, parcel, options)
        end
      end
    end
  end
end
