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
