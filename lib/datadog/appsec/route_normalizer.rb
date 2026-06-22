# frozen_string_literal: true

require_relative 'route_normalizer/route_pattern'
require_relative 'route_normalizer/rails_journey_route'

module Datadog
  module AppSec
    module RouteNormalizer
      GRAPE_ROUTE_KEY = 'grape.routing_args'
      SINATRA_ROUTE_KEY = 'sinatra.route'
      DATADOG_ROUTE_KEY = 'datadog.action_dispatch.route'
      RAILS_ROUTE_KEY = 'action_dispatch.route'
      RAILS_ROUTE_URI_PATTERN_KEY = 'action_dispatch.route_uri_pattern'
      PATH_PARAMS_KEY = 'action_dispatch.request.path_parameters'

      # == Route spec extraction and normalization (RFC-1103)
      #
      # Produces `_dd.appsec.normalized_route` span tag from framework route data.
      # Output: `{mount_prefix}{normalized_route}` per RFC-1103.
      #
      # === Call chain example: Rails POST /posts/1.json
      #
      # env = {
      #   'datadog.action_dispatch.route' => #<Journey::Route>,  # route.path.spec.to_s => "/posts/:id(.:format)"
      #   'action_dispatch.request.path_parameters' => {id: "1", format: "json"},
      #   'PATH_INFO' => '/posts/1.json',
      # }
      #
      # normalized_route(env)
      #   route_spec(env)                                        => "/posts/:id(.:format)"
      #   path_params = {id: "1", format: "json"}
      #   request_path = "/posts/1.json"
      #   normalize("/posts/:id(.:format)", {id: "1", format: "json"}, "/posts/1.json")
      #     resolve_optionals("/posts/:id(.:format)", {id: "1", format: "json"}, "/posts/1.json")
      #       gsub match: "(.:format)" => optional_present?(".:format", ...)
      #         param :format => format_in_url?("json", "/posts/1.json")
      #           String + URL ends with ".json"                 => true
      #         => true, keep group content                      => ".:format"
      #       => "/posts/:id.:format"
      #     split("/", -1) => ["", "posts", ":id.:format"]
      #     normalize_segment("posts")     -> static             => "posts"
      #     normalize_segment(":id.:format") -> scan [:id, :format] => "{id+format}"
      #     join("/")                                            => "/posts/{id+format}"
      #
      # === Call chain example: Rails GET /posts/1 (format absent)
      #
      # path_params = {id: "1", format: nil}, request_path = "/posts/1"
      #
      # normalize("/posts/:id(.:format)", {id: "1", format: nil}, "/posts/1")
      #   resolve_optionals(...)
      #     optional_present?(".:format", ...)
      #       format_in_url?(nil, "/posts/1")                    => false
      #     => false, remove group                               => ""
      #   => "/posts/:id"
      #   normalize_segment(":id")                               => "{id}"
      #   => "/posts/{id}"
      #
      # === Call chain example: Sinatra GET /users/42 mounted at /myapp
      #
      # env = {
      #   'sinatra.route' => 'GET /users/:id',
      #   'PATH_INFO' => '/users/42',
      #   'SCRIPT_NAME' => '/myapp',
      # }
      #
      # normalized_route(env)
      #   route_spec(env)
      #     split("GET /users/:id", " ", 2)[1]                   => "/users/:id"
      #   path_params = {}  (Sinatra doesn't set PATH_PARAMS_KEY)
      #   normalize("/users/:id", {}, "/users/42")
      #     resolve_optionals("/users/:id", ...)
      #       no "(" in spec                                     => "/users/:id" (no-op)
      #     normalize_segment(":id")                             => "{id}"
      #     => "/users/{id}"
      #
      # Middleware prepends SCRIPT_NAME: "/myapp" + "/users/{id}" => "/myapp/users/{id}"
      #
      # === Route spec sources (checked in order by `route_spec`)
      #
      # Grape:   env['grape.routing_args'][:route_info].pattern.origin
      #          => "/api/users/:id"
      #
      # Sinatra: env['sinatra.route']
      #          => "GET /users/:id"  (split on space, take path)
      #
      # Rails:   env['datadog.action_dispatch.route']   (set by tracer, all Rails versions)
      #          env['action_dispatch.route']            (native, Rails 8.1.1+)
      #          Both are Journey::Route objects: route.path.spec.to_s => "/users/:id(.:format)"
      #
      #          env['action_dispatch.route_uri_pattern'] (Rails 7.1-8.0, string)
      #          => "/users/:id(.:format)"
      #
      # Trace:   trace.get_tag('http.route')            (last resort, format already stripped)
      #          => "/users/:id"
      #
      # === Path parameters (Rails only)
      #
      # env['action_dispatch.request.path_parameters'] => {id: "42", format: nil}
      #
      # Keys are always symbols. Values: String = matched from URL, nil/Symbol = from defaults.
      # Used to resolve optional groups. Sinatra/Grape don't set this key (empty hash fallback).
      #
      # === Segment normalization rules
      #
      # All frameworks use `:param` and `*param` syntax. Same rules apply everywhere.
      #
      # "users"       => "users"         (static)
      # ":id"         => "{id}"          (single param)
      # ":id.:format" => "{id+format}"   (multi-param, declaration order)
      # "user-:id"    => "{id}"          (static+param = param wins)
      # "*path"       => "{path}"        (glob)
      # "*"           => "{param1}"      (nameless glob, auto-counter)
      #
      # Rails:   "/users/:id(.:format)"  => "/users/{id}" or "/users/{id+format}"
      #          "/posts(/:year(/:month))" => "/posts", "/posts/{year}", "/posts/{year}/{month}"
      #          "/books/*section/:title" => "/books/{section}/{title}"
      #          Optionals resolved per-request via path_params. Only Rails has `(...)` groups.
      #
      # Sinatra: "/users/:id"           => "/users/{id}"
      #          "/files/*"             => "/files/{param1}"
      #          "/download/*.*"        => "/download/{param1+param2}"  (Sinatra splat syntax)
      #          No optional groups — specs pass through resolve_optionals unchanged.
      #
      # Grape:   "/api/users/:id"       => "/api/users/{id}"
      #          "/status"              => "/status"
      #          No optional groups, no glob syntax in practice.
      #
      # === Mount prefix (handled by middleware, not here)
      #
      # Rails:         trace.get_tag('http.route_path')  => "/api/v2"
      # Sinatra/Grape: env['SCRIPT_NAME']                => "/myapp"
      # Prepended to normalized route by `add_normalized_route_tag`.

      module_function

      def normalized_route(env)
        if env.key?(GRAPE_ROUTE_KEY)
          route_string = env[GRAPE_ROUTE_KEY][:route_info]&.pattern&.origin
          return unless route_string
          RoutePattern.new(route_string).normalize

        elsif env.key?(SINATRA_ROUTE_KEY)
          route_string = env[SINATRA_ROUTE_KEY].split(' ', 2)[1]
          return unless route_string
          RoutePattern.new(route_string).normalize

        elsif (route = env[DATADOG_ROUTE_KEY] || env[RAILS_ROUTE_KEY])
          path_params = env.fetch(PATH_PARAMS_KEY, {})
          request_path = env['PATH_INFO'].to_s
          RailsJourneyRoute.new(path_params, request_path, route: route).normalize

        elsif env.key?(RAILS_ROUTE_URI_PATTERN_KEY)
          path_params = env.fetch(PATH_PARAMS_KEY, {})
          request_path = env['PATH_INFO'].to_s
          RailsJourneyRoute.new(path_params, request_path, route_string: env[RAILS_ROUTE_URI_PATTERN_KEY]).normalize

        elsif defined?(Tracing) && (trace = Tracing.active_trace)
          route_string = trace.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE)
          return unless route_string
          RoutePattern.new(route_string).normalize
        end
      rescue => e
        AppSec.telemetry&.report(e, description: 'Could not compute normalized route')
        nil
      end
    end
  end
end
