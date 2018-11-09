module Datadog
  module Transport
    module HTTP
      # Represents a grouping of routes a part of the same API version.
      # Does some very basic routing based off of parcel type.
      class API
        attr_reader \
          :routes

        def initialize(routes = {})
          @routes = routes
        end

        def deliver(service, parcel, options = {})
          # Send parcel through to the endpoint
          endpoint_for(parcel.class).deliver(service, parcel, options)
        end

        def endpoint_for(key)
          routes[key].tap do |endpoint|
            raise NoEndpointError, key if endpoint.nil?
          end
        end

        # Raised when the API cannot map the request to an endpoint.
        class NoEndpointError < StandardError
          attr_reader :key

          def initialize(key)
            @key = key
          end

          def message
            "No matching transport API endpoint for #{key}!"
          end
        end
      end
    end
  end
end
