# frozen_string_literal: true

module Datadog
  module AppSec
    module RouteNormalizer
      GRAPE_ROUTE_KEY = 'grape.routing_args'
      SINATRA_ROUTE_KEY = 'sinatra.route'
      DATADOG_ROUTE_KEY = 'datadog.action_dispatch.route'
      RAILS_ROUTE_KEY = 'action_dispatch.route'
      RAILS_ROUTE_URI_PATTERN_KEY = 'action_dispatch.route_uri_pattern'
      PATH_PARAMS_KEY = 'action_dispatch.request.path_parameters'

      PARAM_PATTERN = /(?<=:|(?<!\w)\*)\w+/
      OPTIONAL_GROUP_PATTERN = /\(([^()]*)\)/

      UNRESERVED_CHARS = /[^A-Za-z0-9.\-~_\/]/

      module_function

      def normalized_route(env)
        spec = route_spec(env)
        return unless spec

        path_params = env.fetch(PATH_PARAMS_KEY, {})
        request_path = env['PATH_INFO'].to_s

        normalize(spec, path_params, request_path)
      rescue => e
        AppSec.telemetry&.report(e, description: 'Could not compute normalized route')
        nil
      end

      def route_spec(env)
        if env.key?(GRAPE_ROUTE_KEY)
          env[GRAPE_ROUTE_KEY][:route_info]&.pattern&.origin
        elsif env.key?(SINATRA_ROUTE_KEY)
          env[SINATRA_ROUTE_KEY].split(' ', 2)[1]
        elsif (route = env[DATADOG_ROUTE_KEY] || env[RAILS_ROUTE_KEY])
          route.path.spec.to_s
        elsif env.key?(RAILS_ROUTE_URI_PATTERN_KEY)
          env[RAILS_ROUTE_URI_PATTERN_KEY]
        elsif defined?(Tracing) && (trace = Tracing.active_trace)
          trace.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE)
        end
      end

      def normalize(spec, path_params, request_path)
        resolved = resolve_optionals(spec, path_params, request_path)

        result = resolved.split('/').map { |segment| normalize_segment(segment) }.join('/')
        result = "/#{result}" unless result.start_with?('/')
        result
      end

      def resolve_optionals(spec, path_params, request_path)
        result = spec.dup
        while result.include?('(')
          substituted = result.gsub(OPTIONAL_GROUP_PATTERN) do
            group_content = ::Regexp.last_match(1)
            optional_present?(group_content, path_params, request_path) ? group_content : ''
          end
          break if substituted == result

          result = substituted
        end
        result
      end

      def optional_present?(group_content, path_params, request_path)
        param_names = group_content.scan(PARAM_PATTERN).map(&:to_sym)
        return false if param_names.empty?

        param_names.all? do |name|
          if name == :format
            format_in_url?(path_params[:format], request_path)
          else
            value = path_params[name]
            value.is_a?(String)
          end
        end
      end

      def format_in_url?(format_value, request_path)
        case format_value
        when nil then false
        when Symbol then false
        when String then request_path.end_with?(".#{format_value}")
        else false
        end
      end

      def normalize_segment(segment)
        return segment if segment.empty?

        param_names = segment.scan(PARAM_PATTERN)

        if param_names.empty?
          encode_static(segment)
        else
          "{#{param_names.join('+')}}"
        end
      end

      def encode_static(segment)
        segment.gsub(UNRESERVED_CHARS) { |c| "%%%02X" % c.ord }
      end
    end
  end
end
