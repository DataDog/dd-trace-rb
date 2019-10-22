module Datadog
  class Context
    # ThreadLocalContext can be used as a tracer global reference to create
    # a different \Context for each thread. In synchronous tracer, this
    # is required to prevent multiple threads sharing the same \Context
    # in different executions.
    class ThreadLocal
      def initialize
        self.local = Context.new
      end

      # Override the thread-local context with a new context.
      def local=(ctx)
        Thread.current[:datadog_context] = ctx
      end

      # Return the thread-local context.
      def local
        Thread.current[:datadog_context] ||= Context.new
      end
    end
  end
end
