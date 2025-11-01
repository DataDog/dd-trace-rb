# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Rack
        # This module provides logic for inferring HTTP route pattern
        # from an HTTP path.
        module RouteInference
          MAX_NUMBER_OF_SEGMENTS = 8

          INT_PARAM_REGEX = /\A[0-9]+\z/.freeze
          INT_ID_PARAM_REGEX = /\A(?=.*\d)[\d._-]{3,}\z/.freeze
          HEX_PARAM_REGEX = /\A(?=.*\d)[A-Fa-f0-9]{6,}\z/.freeze
          HEX_ID_PARAM_REGEX = /\A(?=.*\d)[A-Fa-f0-9._-]{6,}\z/.freeze
          STRING_PARAM_REGEX = /\A.{20,}|.*[%&'()*+,:=@].*\z/.freeze

          DATADOG_INFERRED_ROUTE_ENV_KEY = 'datadog.inferred_route'

          module_function

          def read_or_infer(request_env)
            request_env[DATADOG_INFERRED_ROUTE_ENV_KEY] ||=
              infer(request_env['SCRIPT_NAME'].to_s + request_env['PATH_INFO'].to_s)
          end

          def infer(path)
            segments = path.delete_prefix('/').split('/', MAX_NUMBER_OF_SEGMENTS + 1).first(MAX_NUMBER_OF_SEGMENTS)

            segments.map! do |segment|
              next if segment.empty?

              case segment
              when INT_PARAM_REGEX then '{param:int}'
              when INT_ID_PARAM_REGEX then '{param:int_id}'
              when HEX_PARAM_REGEX then '{param:hex}'
              when HEX_ID_PARAM_REGEX then '{param:hex_id}'
              when STRING_PARAM_REGEX then '{param:str}'
              else segment
              end
            end

            segments.compact!

            "/#{segments.join("/")}"
          rescue
            nil
          end
        end
      end
    end
  end
end
