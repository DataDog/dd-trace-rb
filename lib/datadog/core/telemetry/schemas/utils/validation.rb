module Datadog
  module Core
    module Telemetry
      module Schemas
        module Utils
          # Contains methods to validate telemetry schema parameters
          module Validation
            def valid_string?(str)
              !str.nil? && str.is_a?(String) && !str.empty?
            end

            def valid_bool?(bool)
              !bool.nil? && [true, false].include?(bool)
            end

            def valid_int?(int)
              !int.nil? && int.is_a?(Integer)
            end

            def valid_optional_string?(str)
              str.nil? || str && valid_string?(str)
            end

            def valid_optional_bool?(bool)
              bool.nil? || [true, false].include?(bool)
            end

            def type_of_array?(array, type)
              array.is_a?(Array) && !array.empty? && array.all? { |item| item.is_a?(type) }
            end
          end
        end
      end
    end
  end
end
