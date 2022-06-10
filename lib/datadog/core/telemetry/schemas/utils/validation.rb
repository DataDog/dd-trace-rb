module Datadog
  module Core
    module Telemetry
      module Schemas
        module Utils
          # Contains methods to validate telemetry schema parameters
          module Validation
            # Checks if argument is non-empty string
            #
            # @param str [any] Value to be validated
            #
            # @!visibility private
            def valid_string?(str)
              !str.nil? && str.is_a?(String) && !str.empty?
            end

            # Checks if argument is a non-nil Boolean (`true` or `false`)
            #
            # @param bool [any] Value to be validated
            #
            # @!visibility private
            def valid_bool?(bool)
              !bool.nil? && [true, false].include?(bool)
            end

            # Checks if argument is a non-nil Integer
            #
            # @param int [any] Value to be validated
            #
            # @!visibility private
            def valid_int?(int)
              !int.nil? && int.is_a?(Integer)
            end

            # Checks if argument is either nil or a non-empty String
            #
            # @param str [any] Value to be validated
            #
            # @!visibility private
            def valid_optional_string?(str)
              str.nil? || str && valid_string?(str)
            end

            # Checks if argument is nil or a valid Boolean (`true` or `false`)
            #
            # @param bool [any] Value to be validated
            #
            # @!visibility private
            def valid_optional_bool?(bool)
              bool.nil? || [true, false].include?(bool)
            end

            # Checks if argument is an array of certain type
            #
            # @param array [Array] Array of objects to be validated
            # @param type [class] Class to compare each item in the array against
            #
            # @!visibility private
            def type_of_array?(array, type)
              array.is_a?(Array) && !array.empty? && array.all? { |item| item.is_a?(type) }
            end
          end
        end
      end
    end
  end
end
