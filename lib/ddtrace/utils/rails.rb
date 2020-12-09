module Datadog
  module Utils
    # Common rails-related utility functions.
    module Rails
      module_function

      def railtie_supported?
        !(defined?(::Rails::VERSION::MAJOR) && ::Rails::VERSION::MAJOR >= 3 && defined?(::Rails::Railtie)).nil?
      end
    end
  end
end
