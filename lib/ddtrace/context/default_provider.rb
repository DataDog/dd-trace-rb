module Datadog
  class Context
    # DefaultProvider is a default context provider that retrieves
    # all contexts from the current thread-local storage. It is suitable for
    # synchronous programming.
    class DefaultProvider
      # Initializes the default context provider with a thread-bound context.
      def initialize
        @context = Datadog::Context::ThreadLocal.new
      end

      # Sets the current context.
      def context=(ctx)
        @context.local = ctx
      end

      # Return the current context.
      def context
        @context.local
      end
    end
  end
end
