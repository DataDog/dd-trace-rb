require 'ddtrace/ext/environment'

module Datadog
  # Namespace for handling application environment
  module Environment
    # Defines helper methods for environment
    module Helpers
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

      def env_to_list(var, default = [])
        var = decode_array(var)
        if var && ENV.key?(var)
          ENV[var].split(',').map(&:strip)
        else
          default
        end
      end

      private

      def decode_array(var)
        var.is_a?(Array) ? var.find { |env_var| ENV.key?(env_var) } : var
      end
    end

    extend Helpers
  end
end
