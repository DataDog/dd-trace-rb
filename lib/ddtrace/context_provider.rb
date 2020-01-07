module Datadog
  # DefaultContextProvider is a default context provider that retrieves
  # all contexts from the current thread-local storage. It is suitable for
  # synchronous programming.
  class DefaultContextProvider
    # Initializes the default context provider with a thread-bound context.
    def initialize
      @context = ThreadLocalContext.new
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

  # ThreadLocalContext can be used as a tracer global reference to create
  # a different \Context for each thread. In synchronous tracer, this
  # is required to prevent multiple threads sharing the same \Context
  # in different executions.
  class ThreadLocalContext
    # ThreadLocalContext can be used as a tracer global reference to create
    # a different \Context for each thread. In synchronous tracer, this
    # is required to prevent multiple threads sharing the same \Context
    # in different executions.
    def initialize
      self.local = Datadog::Context.new
    end

    # Override the thread-local context with a new context.
    def local=(ctx)
      Thread.current[:datadog_context] = ctx
    end

    # Return the thread-local context.
    def local
      Thread.current[:datadog_context] ||= Datadog::Context.new
    end
  end
end
