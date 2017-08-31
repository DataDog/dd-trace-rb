module Datadog
  # DefaultContextProvider is a default context provider that retrieves
  # all contexts from the current thread-local storage. It is suitable for
  # synchronous programming.
  class DefaultContextProvider
    # Initializes the default context provider with a thread-bound context.
    def initialize
      @context = Datadog::ThreadLocalContext.new
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
