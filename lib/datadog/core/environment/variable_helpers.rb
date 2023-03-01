module Datadog
  module Core
    # Namespace for handling application environment
    module Environment
      # Defines helper methods for environment
      # @public_api
      module VariableHelpers
        extend self

        # Reads an environment variable as a Boolean.
        #
        # @param [String] var environment variable
        # @param [Array<String>] var list of environment variables
        # @param [Boolean] default the default value if the keys in `var` are not present in the environment
        # @param [Boolean] deprecation_warning when `var` is a list, record a deprecation log when
        #   the first key in `var` is not used.
        # @return [Boolean] if the environment value is the string `true`
        # @return [default] if the environment value is not found
        def env_to_bool(var, default = nil, deprecation_warning: true)
          var = decode_array(var, deprecation_warning)
          var && ENV.key?(var) ? ENV[var].to_s.strip.downcase == 'true' : default
        end

        # Reads an environment variable as an Integer.
        #
        # @param [String] var environment variable
        # @param [Array<String>] var list of environment variables
        # @param [Integer] default the default value if the keys in `var` are not present in the environment
        # @param [Boolean] deprecation_warning when `var` is a list, record a deprecation log when
        #   the first key in `var` is not used.
        # @return [Integer] if the environment value is a valid Integer
        # @return [default] if the environment value is not found
        def env_to_int(var, default = nil, deprecation_warning: true)
          var = decode_array(var, deprecation_warning)
          var && ENV.key?(var) ? ENV[var].to_i : default
        end

        # Reads an environment variable as a Float.
        #
        # @param [String] var environment variable
        # @param [Array<String>] var list of environment variables
        # @param [Float] default the default value if the keys in `var` are not present in the environment
        # @param [Boolean] deprecation_warning when `var` is a list, record a deprecation log when
        #   the first key in `var` is not used.
        # @return [Float] if the environment value is a valid Float
        # @return [default] if the environment value is not found
        def env_to_float(var, default = nil, deprecation_warning: true)
          var = decode_array(var, deprecation_warning)
          var && ENV.key?(var) ? ENV[var].to_f : default
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
        # @param [String] var environment variable
        # @param [Array<String>] var list of environment variables
        # @param [Array<Object>] default the default value if the keys in `var` are not present in the environment
        # @param [Boolean] deprecation_warning when `var` is a list, record a deprecation log when
        #   the first key in `var` is not used.
        # @return [Array<Object>] if the environment value is a valid list
        # @return [default] if the environment value is not found
        def env_to_list(var, default = [], comma_separated_only:, deprecation_warning: true)
          var = decode_array(var, deprecation_warning)
          if var && ENV.key?(var)
            value = ENV[var]

            values = if value.include?(',') || comma_separated_only
                       value.split(',')
                     else
                       value.split(' ') # rubocop:disable Style/RedundantArgument
                     end

            values.map! do |v|
              v.gsub!(/\A[\s,]*|[\s,]*\Z/, '')

              v.empty? ? nil : v
            end

            values.compact!
            values
          else
            default
          end
        end

        private

        def decode_array(var, deprecation_warning)
          if var.is_a?(Array)
            var.find.with_index do |env_var, i|
              found = ENV.key?(env_var)

              # Check if we are using a non-preferred environment variable
              if deprecation_warning && found && i != 0
                Datadog::Core.log_deprecation { "#{env_var} environment variable is deprecated, use #{var.first} instead." }
              end

              found
            end
          else
            var
          end
        end
      end
    end
  end
end
