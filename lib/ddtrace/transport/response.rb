module Datadog
  module Transport
    # Defines abstract response for transport operations
    module Response
      def payload
        nil
      end

      def ok?
        false
      end

      def unsupported?
        false
      end

      def not_found?
        false
      end

      def client_error?
        false
      end

      def server_error?
        false
      end

      def internal_error?
        false
      end
    end
  end
end
