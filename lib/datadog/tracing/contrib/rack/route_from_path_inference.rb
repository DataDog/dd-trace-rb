# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Rack
        # This module provides logic for inferring HTTP route pattern
        # from an HTTP path.
        module RouteFromPathInference
          MAX_NUMBER_OF_SEGMENTS = 8

          INT_PARAM_REGEX = /\A[1-9][0-9]+\z/.freeze
          INT_ID_PARAM_REGEX = /\A(?=.*\d)[\d._-]{3,}\z/.freeze
          HEX_PARAM_REGEX = /\A(?=.*\d)[A-Fa-f0-9]{6,}\z/.freeze
          HEX_ID_PARAM_REGEX = /\A(?=.*\d)[A-Fa-f0-9._-]{6,}\z/.freeze
          STRING_PARAM_REGEX = /\A.{20,}|.*[%&'()*+,:=@].*\z/.freeze

          module_function

          def infer(path)
            segments = path.delete_prefix('/').split('/')

            segments.map!.with_index do |segment, index|
              next segment if index >= MAX_NUMBER_OF_SEGMENTS

              case segment
              when INT_PARAM_REGEX
                '{param:int}'
              when INT_ID_PARAM_REGEX
                '{param:int_id}'
              when HEX_PARAM_REGEX
                '{param:hex}'
              when HEX_ID_PARAM_REGEX
                '{param:hex_id}'
              when STRING_PARAM_REGEX
                '{param:str}'
              else
                segment
              end
            end

            '/' + segments.join('/')
          rescue
            nil
          end
        end
      end
    end
  end
end
