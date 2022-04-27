# typed: true

require 'datadog/tracing/context'

module Datadog
  module Tracing
    # DefaultContextProvider is a default context provider that retrieves
    # all contexts from the current fiber-local storage. It is suitable for
    # synchronous programming.
    #
    # @see https://ruby-doc.org/core-3.1.2/Thread.html#method-i-5B-5D Thread attributes are fiber-local
    class DefaultContextProvider
      # Initializes the default context provider with a fiber-bound context.
      def initialize
        @context = FiberLocalContext.new
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

    # FiberLocalContext can be used as a tracer global reference to create
    # a different {Datadog::Tracing::Context} for each fiber. This allows for the tracer
    # to create a serial execution graph regardless of any concurrent execution: each
    # concurrent execution path creates a new trace graph.
    #
    # @see https://ruby-doc.org/core-3.1.2/Thread.html#method-i-5B-5D Thread attributes are fiber-local
    class FiberLocalContext
      # To support multiple tracers simultaneously, each {Datadog::Tracing::FiberLocalContext}
      # instance has its own fiber-local variable.
      def initialize
        @key = "datadog_context_#{object_id}".to_sym

        self.local = Context.new
      end

      # Override the fiber-local context with a new context.
      def local=(ctx)
        Thread.current[@key] = ctx
      end

      # Return the fiber-local context.
      def local(storage = Thread.current)
        storage[@key] ||= Context.new
      end
    end
  end
end
