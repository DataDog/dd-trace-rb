module Datadog
  module Transport
    module HTTP
      module API
        # An API configured with adapter and routes
        class Instance
          attr_reader \
            :adapter,
            :headers,
            :routes

          def initialize(adapter, routes, options = {})
            @adapter = adapter
            @routes = routes
            @headers = options.fetch(:headers, {})
          end

          def call(env)
            # Find matching route
            path, endpoint = route!(env)

            # Apply path to request
            env.path = path

            # Deliver request
            endpoint.call(env) do |request_env|
              adapter.call(request_env)
            end
          end

          def route!(env)
            # Find route
            routes[env.request.route].tap do |destination|
              raise NoRouteError, key if destination.nil?
            end
          end

          # Raised when the API cannot map the request to an endpoint.
          class NoRouteError < StandardError
            attr_reader :key

            def initialize(key)
              @key = key
            end

            def message
              "No matching transport route for #{key}!"
            end
          end
        end
      end
    end
  end
end
