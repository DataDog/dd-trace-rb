# typed: true

require 'datadog/tracing/context'

module Datadog
  module Tracing
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
    # a different {Datadog::Tracing::Context} for each thread. In synchronous tracer, this
    # is required to prevent multiple threads sharing the same {Datadog::Tracing::Context}
    # in different executions.
    class ThreadLocalContext
      # ThreadLocalContext can be used as a tracer global reference to create
      # a different {Datadog::Tracing::Context} for each thread. In synchronous tracer, this
      # is required to prevent multiple threads sharing the same {Datadog::Tracing::Context}
      # in different executions.
      #
      # To support multiple tracers simultaneously, each {Datadog::Tracing::ThreadLocalContext}
      # instance has its own thread-local variable.
      def initialize
        @key = "datadog_context_#{object_id}".to_sym

        self.local = Context.new
      end

      # Override the thread-local context with a new context.
      def local=(ctx)
        Thread.current[@key] = ctx
      end

      # Return the thread-local context.
      def local(thread = Thread.current)
        thread[@key] ||= Context.new
      end
    end
  end
end
