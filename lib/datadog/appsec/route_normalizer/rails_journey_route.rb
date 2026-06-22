# frozen_string_literal: true

require_relative 'string_route'
require_relative 'route_text'

module Datadog
  module AppSec
    module RouteNormalizer
      class RailsJourneyRoute
        OPTIONAL_GROUP_PATTERN = /\(([^()]*)\)/
        PARAM_PATTERN = /(?<=:|(?<!\w)\*)\w+/

        def initialize(path_params, request_path, route: nil, route_string: nil)
          @route = route
          @route_string = route_string
          @path_params = path_params
          @request_path = request_path
        end

        def normalize
          if @route
            normalize_ast
          elsif @route_string
            normalize_string
          end
        end

        private

        def normalize_ast
          if @route.path.names.empty?
            spec_string = @route.path.spec.to_s
            return RouteText.escape(spec_string) unless spec_string.include?('(')
          end

          @result = +''
          @static = +''
          @names = []
          @has_param = false
          @parts = 0
          @nameless_counter = 0

          visit(@route.path.spec)
          flush_segment

          @result = "/#{@result}" unless @result.start_with?('/')
          @result
        end

        def visit(node)
          case node.type
          when :CAT
            visit(node.left)
            visit(node.right)
          when :SLASH
            flush_segment
          when :LITERAL
            @static << node.left
          when :DOT
            @static << '.'
          when :SYMBOL, :STAR
            @has_param = true
            @names << node.name
          when :GROUP
            visit(node.left) if group_present?(node.left)
          end
        end

        def flush_segment
          @result << '/' if @parts > 0
          @result << (@has_param ? render_params : RouteText.escape(@static))
          @parts += 1

          @static.clear
          @names.clear
          @has_param = false
        end

        def render_params
          names = @names.map { |name| name.empty? ? "param#{@nameless_counter += 1}" : name }
          "{#{names.join('+')}}"
        end

        def group_present?(node)
          params = direct_params(node)
          !params.empty? && params.all? { |param| param_present?(param.name.to_sym) }
        end

        def direct_params(node, acc = [])
          case node.type
          when :SYMBOL, :STAR
            acc << node
          when :CAT
            direct_params(node.left, acc)
            direct_params(node.right, acc)
          when :GROUP
            # stop — nested group resolves independently
          end
          acc
        end

        def normalize_string
          StringRoute.new(resolve_optionals(@route_string)).normalized
        end

        def resolve_optionals(route_string)
          result = route_string.dup
          while result.include?('(')
            substituted = result.gsub(OPTIONAL_GROUP_PATTERN) do
              group_content = ::Regexp.last_match(1)
              optional_present?(group_content) ? group_content : ''
            end
            break if substituted == result

            result = substituted
          end
          result
        end

        def optional_present?(group_content)
          param_names = group_content.scan(PARAM_PATTERN).map(&:to_sym)
          return false if param_names.empty?

          param_names.all? { |name| param_present?(name) }
        end

        def param_present?(name)
          if name == :format
            format_in_url?(@path_params[:format])
          else
            @path_params[name].is_a?(String)
          end
        end

        def format_in_url?(format_value)
          case format_value
          when nil then false
          when Symbol then false
          when String then @request_path.end_with?(".#{format_value}")
          else false
          end
        end
      end
    end
  end
end
