# frozen_string_literal: true

require_relative 'route_text'
require_relative 'route_pattern'

module Datadog
  module AppSec
    module RouteNormalizer
      # Normalizes Rails route patterns into route format, inspired by
      # OpenAPI v3 path templating
      #
      # NOTE: Uses the parsed Journey AST when available
      #
      # @api private
      class RailsRoutePattern
        DOT_CHAR = '.'
        GROUP_OPEN_CHAR = '('
        OPTIONAL_GROUP_PATTERN = /\(([^()]*)\)/
        NAMED_PARAM_PREFIX_CHAR = ':'
        GLOB_PARAM_PREFIX_CHAR = '*'

        def initialize(pattern)
          @pattern = pattern
        end

        def normalize(path_params:, request_path:)
          @path_params = path_params
          @request_path = request_path
          @nameless_param_count = 0

          @segments = []
          @segment_text = +''
          @segment_params = []

          if @pattern.is_a?(String)
            # NOTE: Journey groups without route params are never kept
            #       Example: `/foo(/bar)` with request `/foo/bar` normalizes to `/foo`
            pattern = remove_paramless_optional_groups(@pattern)
            return RoutePattern.new(pattern).normalize(request_path: request_path)
          end

          route_path = @pattern.path
          route_spec = route_path.spec

          unless route_spec.respond_to?(:type)
            return RoutePattern.new(route_spec.to_s).normalize(request_path: request_path)
          end

          if route_path.names.empty?
            route_string = route_spec.to_s
            return RouteText.escape(route_string) unless route_string.include?(GROUP_OPEN_CHAR)
          end

          visit_route_node(route_spec)
          finish_segment

          "/#{@segments.join('/')}"
        end

        private

        def remove_paramless_optional_groups(pattern)
          result = pattern

          loop do
            substituted = result.gsub(OPTIONAL_GROUP_PATTERN) do
              group = ::Regexp.last_match(1)
              optional_group_has_route_params?(group) ? "(#{group})" : ''
            end

            return result if substituted == result

            result = substituted
          end
        end

        def visit_route_node(node)
          case node.type
          when :CAT
            visit_route_node(node.left)
            visit_route_node(node.right)
          when :SLASH
            finish_segment
          when :LITERAL
            @segment_text << node.left
          when :DOT
            @segment_text << DOT_CHAR
          when :SYMBOL, :STAR
            @segment_params << node.name
          when :GROUP
            visit_route_node(node.left) if group_present?(node.left)
          end
        end

        def finish_segment
          return if @segment_text.empty? && @segment_params.empty?

          @segments << if @segment_params.empty?
            RouteText.escape(@segment_text)
          else
            render_segment_params(@segment_params)
          end

          @segment_text = +''
          @segment_params.clear
        end

        def render_segment_params(params)
          names = params.map do |name|
            next name unless name.empty?

            @nameless_param_count += 1
            "param#{@nameless_param_count}"
          end

          "{#{names.join('+')}}"
        end

        def group_present?(node)
          param_names = collect_group_param_names(node, [])
          return false if param_names.empty?

          param_names.all? { |name| param_matched_request_path?(name.to_sym) }
        end

        def param_matched_request_path?(name)
          return @path_params[name].is_a?(String) unless name == :format

          format = @path_params[:format]
          return false if !format.is_a?(String) || format.empty?

          dot_index = @request_path.length - format.length - 1
          return false if dot_index < 0 || @request_path[dot_index] != DOT_CHAR

          @request_path.end_with?(format)
        end

        def collect_group_param_names(node, memo)
          case node.type
          when :SYMBOL, :STAR
            memo << node.name
          when :CAT
            collect_group_param_names(node.left, memo)
            collect_group_param_names(node.right, memo)
          end

          memo
        end

        def optional_group_has_route_params?(group)
          group.include?(NAMED_PARAM_PREFIX_CHAR) || group.include?(GLOB_PARAM_PREFIX_CHAR)
        end
      end
    end
  end
end
