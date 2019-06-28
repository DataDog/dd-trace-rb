module Datadog
  module Transport
    # Defines abstract response for transport operations
    module Response
      def payload
        nil
      end

      def ok?
        nil
      end

      def unsupported?
        nil
      end

      def not_found?
        nil
      end

      def client_error?
        nil
      end

      def server_error?
        nil
      end

      def internal_error?
        nil
      end
    end

    # A generic error response for internal errors
    class InternalErrorResponse
      include Response

      attr_reader :error

      def initialize(error)
        @error = error
      end

      def internal_error?
        true
      end
    end
  end
end
