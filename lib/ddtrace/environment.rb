module Datadog
  # Namespace for handling application environment
  module Environment
    # Defines helper methods for environment
    module Helpers
      def env_to_bool(var, default = nil)
        ENV.key?(var) ? ENV[var].to_s.downcase == 'true' : default
      end

      def env_to_float(var, default = nil)
        ENV.key?(var) ? ENV[var].to_f : default
      end
    end
  end
end
