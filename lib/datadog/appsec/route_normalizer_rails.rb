# frozen_string_literal: true

module Datadog
  module AppSec
    module RouteNormalizer
      module Rails
        UNRESERVED_CHARS = RouteNormalizer::UNRESERVED_CHARS

        module_function

        def normalize(route, path_params, request_path)
          return encode_static(route.path.spec.to_s) if route.path.names.empty?

          segments = collect_segments(route.path.spec, path_params, request_path)
          nameless_counter = 0

          parts = segments.map do |items|
            param_names = []
            items.each { |type, value| param_names << value if type == :param }

            if param_names.empty?
              static_text = items.map { |_, text| text }.join
              encode_static(static_text)
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

        class << self
          private

          def collect_segments(node, path_params, request_path)
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
                  if param_nodes.all? { |pn| param_present?(pn.name.to_sym, path_params, request_path) }
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

          def param_present?(name, path_params, request_path)
            if name == :format
              format_in_url?(path_params[:format], request_path)
            else
              path_params[name].is_a?(String)
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

          def encode_static(segment)
            segment.gsub(UNRESERVED_CHARS) { |c| c.bytes.map { |b| "%%%02X" % b }.join }
          end
        end
      end
    end
  end
end
