# frozen_string_literal: true

require_relative "route_normalizer/route_pattern"
require_relative "route_normalizer/rails_route_pattern"

module Datadog
  module AppSec
    # Extracts framework route data from Rack env and normalizes it into
    # OpenAPI v3 compatible route format
    #
    # @api private
    module RouteNormalizer
      GRAPE_ROUTE_KEY = "grape.routing_args"
      SINATRA_ROUTE_KEY = "sinatra.route"
      DATADOG_ROUTE_KEY = "datadog.action_dispatch.route"
      RAILS_ROUTE_KEY = "action_dispatch.route"
      RAILS_ROUTE_URI_PATTERN_KEY = "action_dispatch.route_uri_pattern"
      RAILS_PATH_PARAMS_KEY = "action_dispatch.request.path_parameters"

      module_function

      # Extracts a normalized route path for a Rack request.
      #
      # Examples:
      #
      #   Grape:   "/api/users/:id"              => "/api/users/{id}"
      #   Sinatra: "GET /download/*.*"           => "/download/{param1+param2}"
      #   Rails:   "/posts/:id(.:format)" + path => "/posts/{id+format}"
      #   Pattern: "/users/:id"                  => "/users/{id}"
      def extract_normalized_route(rack_env, prefix: nil, pattern: nil)
        route_prefix = prefix || rack_env["SCRIPT_NAME"]

        if rack_env.key?(GRAPE_ROUTE_KEY)
          route_info = rack_env[GRAPE_ROUTE_KEY][:route_info]
          normalize_route_string(route_info&.pattern&.origin)
        elsif rack_env.key?(SINATRA_ROUTE_KEY)
          normalize_route_string(rack_env[SINATRA_ROUTE_KEY].split(" ", 2)[1])
        elsif (rails_route = rack_env[DATADOG_ROUTE_KEY] || rack_env[RAILS_ROUTE_KEY])
          normalize_rails_route(rails_route, rack_env, route_prefix)
        elsif rack_env.key?(RAILS_ROUTE_URI_PATTERN_KEY)
          normalize_rails_route(rack_env[RAILS_ROUTE_URI_PATTERN_KEY], rack_env, route_prefix)
        else
          normalize_route_string(pattern)
        end
      rescue => e
        AppSec.telemetry&.report(e, description: "AppSec: Could not compute normalized route")

        nil
      end

      private_class_method def normalize_rails_route(route, rack_env, route_prefix)
        path_params = rack_env.fetch(RAILS_PATH_PARAMS_KEY, {})
        path = path_without_prefix(rack_env["PATH_INFO"].to_s, route_prefix)

        RailsRoutePattern.new(route).normalize(path_params: path_params, path: path)
      end

      private_class_method def normalize_route_string(route)
        return unless route

        RoutePattern.new(route).normalize
      end

      private_class_method def path_without_prefix(path, prefix)
        return path unless prefix

        prefix = prefix.to_s
        return path if prefix.empty? || prefix == "/"
        return path unless path.start_with?(prefix)

        next_char = path[prefix.length]
        return path if next_char && next_char != "/"

        # NOTE: `start_with?` guards impossible `nil` case
        stripped = path[prefix.length..-1] # : String
        stripped.empty? ? "/" : stripped
      end
    end
  end
end
