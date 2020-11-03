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

    # Return the local context.
    def context(key = nil)
      current_context = key.nil? ? @context.local : @context.local(key)

      # Rebuild/reset context after a fork
      #
      # We don't want forked processes to copy and retransmit spans
      # that were generated from the parent process. Reset it such
      # that it acts like a distributed trace.
      current_context.after_fork! do
        current_context = self.context = current_context.fork_clone
      end

      current_context
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
    #
    # To support multiple tracers simultaneously, each \ThreadLocalContext
    # instance has its own thread-local variable.
    def initialize
      @key = "datadog_context_#{object_id}".to_sym

      self.local = Datadog::Context.new
    end

    # Override the thread-local context with a new context.
    def local=(ctx)
      Thread.current[@key] = ctx
    end

    # Return the thread-local context.
    def local(thread = Thread.current)
      raise ArgumentError, '\'thread\' must be a Thread.' unless thread.is_a?(Thread)
      thread[@key] ||= Datadog::Context.new
    end
  end
end
