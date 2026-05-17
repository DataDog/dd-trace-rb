# frozen_string_literal: true

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
          return StringRoute.encode_static(@route.path.spec.to_s) if @route.path.names.empty?

          segments = collect_segments(@route.path.spec)
          nameless_counter = 0

          parts = segments.map do |items|
            param_names = []
            items.each { |type, value| param_names << value if type == :param }

            if param_names.empty?
              static_text = items.map { |_, text| text }.join
              StringRoute.encode_static(static_text)
            else
              names = param_names.map do |name|
                if name.empty?
                  nameless_counter += 1
                  "param#{nameless_counter}"
                else
                  name
                end
              end
              "{#{names.join('+')}}"
            end
          end

          result = parts.join('/')
          result = "/#{result}" unless result.start_with?('/')
          result
        end

        def normalize_string
          resolved = resolve_optionals(@route_string)
          StringRoute.normalize(resolved)
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

        def collect_segments(node)
          segments = [[]]

          visit = ->(n) {
            case n.type
            when :CAT
              visit.call(n.left)
              visit.call(n.right)
            when :SLASH
              segments << []
            when :LITERAL
              segments.last << [:static, n.left]
            when :DOT
              segments.last << [:static, '.']
            when :SYMBOL
              segments.last << [:param, n.name]
            when :STAR
              segments.last << [:param, n.name]
            when :GROUP
              param_nodes = direct_params(n.left)

              unless param_nodes.empty?
                if param_nodes.all? { |pn| param_present?(pn.name.to_sym) }
                  visit.call(n.left)
                end
              end
            end
          }

          visit.call(node)
          segments
        end

        def direct_params(node)
          result = []
          collect = ->(n) {
            case n.type
            when :SYMBOL, :STAR
              result << n
            when :CAT
              collect.call(n.left)
              collect.call(n.right)
            when :GROUP
              # stop — nested group resolves independently
            end
          }
          collect.call(node)
          result
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
