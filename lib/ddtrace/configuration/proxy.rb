module Datadog
  class Configuration
    # Proxy provides a hash-like interface for fetching/setting configurations
    class Proxy
      def initialize(integration)
        @integration = integration
      end

      def [](param)
        @integration.get_option(param)
      end

      def []=(param, value)
        @integration.set_option(param, value)
      end

      def to_h
        @integration.to_h
      end

      alias to_hash to_h

      def reset!
        @integration.reset_options!
      end
    end
  end
end
