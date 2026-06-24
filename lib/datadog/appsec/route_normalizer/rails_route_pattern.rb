# frozen_string_literal: true

require_relative 'route_pattern'
require_relative 'route_text'

module Datadog
  module AppSec
    module RouteNormalizer
      class RailsRoutePattern
        GROUP_OPEN_CHAR = '('
        OPTIONAL_GROUP_PATTERN = /\(([^()]*)\)/
        PARAM_PATTERN = /(?<=:|(?<!\w)\*)\w+/

        def initialize(pattern)
          @pattern = pattern
        end

        def normalize(path_params:, request_path:)
          param_present = lambda do |name|
            if name == :format
              format = path_params[:format]
              format.is_a?(String) && request_path.end_with?(".#{format}")
            else
              path_params[name].is_a?(String)
            end
          end

          if @pattern.is_a?(String)
            route_string = @pattern.dup

            while route_string.include?(GROUP_OPEN_CHAR)
              substituted = route_string.gsub(OPTIONAL_GROUP_PATTERN) do
                group_content = ::Regexp.last_match(1)
                param_names = group_content.scan(PARAM_PATTERN).map(&:to_sym)

                if param_names.empty? || !param_names.all? { |name| param_present.call(name) }
                  ''
                else
                  group_content
                end
              end
              break if substituted == route_string

              route_string = substituted
            end

            return RoutePattern.new(route_string).normalize
          end

          if @pattern.path.names.empty?
            route_string = @pattern.path.spec.to_s
            return RouteText.escape(route_string) unless route_string.include?(GROUP_OPEN_CHAR)
          end

          result = +''
          segment_static = +''
          segment_params = []
          segment_count = 0
          nameless_param_count = 0

          flush_segment = lambda do
            result << '/' if segment_count > 0

            if segment_params.empty?
              result << RouteText.escape(segment_static)
            else
              names = segment_params.map do |name|
                next name unless name.empty?

                nameless_param_count += 1
                "param#{nameless_param_count}"
              end

              result << "{#{names.join('+')}}"
            end

            segment_count += 1
            segment_static.clear
            segment_params.clear
          end

          collect_direct_params = nil
          collect_direct_params = lambda do |node, names|
            case node.type
            when :SYMBOL, :STAR
              names << node.name
            when :CAT
              collect_direct_params.call(node.left, names)
              collect_direct_params.call(node.right, names)
            end

            names
          end

          group_present = lambda do |node|
            names = collect_direct_params.call(node, [])
            !names.empty? && names.all? { |name| param_present.call(name.to_sym) }
          end

          visit = nil
          visit = lambda do |node|
            case node.type
            when :CAT
              visit.call(node.left)
              visit.call(node.right)
            when :SLASH
              flush_segment.call
            when :LITERAL
              segment_static << node.left
            when :DOT
              segment_static << '.'
            when :SYMBOL, :STAR
              segment_params << node.name
            when :GROUP
              visit.call(node.left) if group_present.call(node.left)
            end
          end

          visit.call(@pattern.path.spec)
          flush_segment.call

          result.start_with?('/') ? result : "/#{result}"
        end
      end
    end
  end
end
