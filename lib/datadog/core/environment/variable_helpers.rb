# typed: false

module Datadog
  module Core
    # Namespace for handling application environment
    module Environment
      # Defines helper methods for environment
      # @public_api
      module VariableHelpers
        extend self

        def env_to_bool(var, default = nil)
          var = decode_array(var)
          var && ENV.key?(var) ? ENV[var].to_s.strip.downcase == 'true' : default
        end

        def env_to_int(var, default = nil)
          var = decode_array(var)
          var && ENV.key?(var) ? ENV[var].to_i : default
        end

        def env_to_float(var, default = nil)
          var = decode_array(var)
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
        def env_to_list(var, default = [], comma_separated_only:)
          var = decode_array(var)
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

        def decode_array(var)
          var.is_a?(Array) ? var.find { |env_var| ENV.key?(env_var) } : var
        end
      end
    end
  end
end
