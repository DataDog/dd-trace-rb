# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Helper methods handling type coercion
      module VariableHelpers
        module_function

        # Cast a variable into a true boolean.
        #
        # @param [Object] val
        # @return [Boolean] if the value is the string `true` or `1` or if the value is thruthy
        def val_to_bool(val)
          case val
          when String
            value = val.dup
            value.strip!
            value.downcase!
            value == 'true' || value == '1' # rubocop:disable Style/MultipleComparison
          when FalseClass || TrueClass
            val
          else
            val ? true : false
          end
        end

        # Cast a variable into an Integer.
        #
        # @param [Object] val
        # @return [Integer] the val as a valid Integer
        def val_to_int(val)
          Integer(val) if val
        rescue ArgumentError => e
          raise e.class, "Value `#{val}` can not be converted to Integer"
        end

        # Cast a variable into a Float.
        #
        # @param [Object] val
        # @return [Float] the val as a valid Float
        def val_to_float(val)
          Float(val) if val
        rescue ArgumentError => e
          raise e.class, "Value `#{val}` can not be converted to Float"
        end

        # Parses comma- or space-separated lists.
        #
        # If a comma is present, then the list is considered comma-separated.
        # Otherwise, it is considered space-separated.
        #
        # After the entries are separated, commas and whitespaces that are
        # either trailing or leading are trimmed.
        #
        # Empty entries, after trimmed, are also removed from the result.
        #
        # @param [String, Array<Object>] val environment variable
        # @param [Array<Object>] default the default value if the keys in `var` are not present in the environment
        # @return [Array<Object>] if the environment value is a valid list
        # @return [default] if the environment value is not found
        def val_to_list(val, default = [], comma_separated_only:)
          if val
            values = case val
                     when String
                       if val.include?(',') || comma_separated_only
                         val.split(',')
                       else
                         val.split(' ') # rubocop:disable Style/RedundantArgument
                       end
                     else
                       begin
                         Array(val)
                       rescue ArgumentError => e
                         raise e.class, "Value `#{val}` can not be converted to an Array"
                       end
                     end

            result = values.map do |v|
              if v.is_a?(String)
                v.gsub!(/\A[\s,]*|[\s,]*\Z/, '')

                v.empty? ? nil : v
              else
                v
              end
            end

            result.compact!
            result
          else
            default
          end
        end
      end
    end
  end
end
