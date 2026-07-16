# frozen_string_literal: true

require_relative "route_text"
require_relative "route_pattern"

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
        DOT_CHAR = "."
        GROUP_OPEN_CHAR = "("
        OPTIONAL_GROUP_PATTERN = /\(([^()]*)\)/
        NAMED_PARAM_PREFIX_CHAR = ":"
        GLOB_PARAM_PREFIX_CHAR = "*"

        def initialize(pattern)
          @pattern = pattern
        end

        def normalize(path_params:, path:)
          @path_params = path_params
          @path = path

          if @pattern.is_a?(String)
            # NOTE: Journey groups without route params are never kept
            #       Example: `/foo(/bar)` with request `/foo/bar` normalizes to `/foo`
            pattern = remove_paramless_optional_groups(@pattern)
            return RoutePattern.new(pattern).normalize(path: path)
          end

          route_path = @pattern.path
          route_spec = route_path.spec

          unless route_spec.respond_to?(:type)
            return RoutePattern.new(route_spec.to_s).normalize(path: path)
          end

          if route_path.names.empty?
            route_string = route_spec.to_s
            return RouteText.escape(route_string) unless route_string.include?(GROUP_OPEN_CHAR)
          end

          buffer = Buffer.new
          visit_route_node(route_spec, buffer)
          buffer.to_path
        end

        private

        def remove_paramless_optional_groups(pattern)
          result = pattern

          loop do
            substituted = result.gsub(OPTIONAL_GROUP_PATTERN) do
              # NOTE: OPTIONAL_GROUP_PATTERN always captures a string for each gsub match
              group = ::Regexp.last_match(1) # : String
              optional_group_has_route_params?(group) ? "(#{group})" : ""
            end

            return result if substituted == result

            result = substituted
          end
        end

        def visit_route_node(node, buffer)
          case node.type
          when :CAT
            visit_route_node(node.left, buffer)
            visit_route_node(node.right, buffer)
          when :SLASH
            buffer.flush
          when :LITERAL
            buffer.add_literal(node.left)
          when :DOT
            buffer.add_literal(DOT_CHAR)
          when :SYMBOL, :STAR
            buffer.add_param(node.name)
          when :GROUP
            visit_route_node(node.left, buffer) if group_present?(node.left)
          end
        end

        def group_present?(node)
          param_names = collect_group_param_names(node, [])
          return false if param_names.empty?

          param_names.all? { |name| param_matched_path?(name.to_sym) }
        end

        def param_matched_path?(name)
          return @path_params[name].is_a?(String) unless name == :format

          format = @path_params[:format]
          return false if !format.is_a?(String) || format.empty?

          dot_index = @path.length - format.length - 1
          return false if dot_index < 0 || @path[dot_index] != DOT_CHAR

          @path.end_with?(format)
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

        class Buffer
          def initialize
            @segments = []
            @text = +""
            @params = []
            @nameless_param_count = 0
          end

          def add_literal(text)
            @text << text
          end

          def add_param(name)
            @params << name
          end

          def flush
            return if @text.empty? && @params.empty?

            @segments << if @params.empty?
              RouteText.escape(@text)
            else
              render_params(@params)
            end

            @text = +""
            @params.clear
          end

          def to_path
            flush

            "/#{@segments.join('/')}"
          end

          private

          def render_params(params)
            names = params.map do |name| # $ String
              next name unless name.empty?

              @nameless_param_count += 1
              "param#{@nameless_param_count}"
            end

            "{#{names.join('+')}}"
          end
        end
      end
    end
  end
end
