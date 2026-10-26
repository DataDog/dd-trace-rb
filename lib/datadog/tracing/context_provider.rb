# frozen_string_literal: true

require_relative "../core/utils/sequence"
require_relative "context"

module Datadog
  module Tracing
    # A concurrency-safe repository for storing and retrieving the current trace context.
    class DefaultContextProvider
      # @param scope [ContextScope] the scope to use for context storage.
      #   The scope defines the lifecycle of the context.
      def initialize(otel_thread_context: nil, scope: FiberIsolatedScope.new(otel_thread_context: otel_thread_context))
        @otel_thread_context = otel_thread_context
        @context = scope
      end

      # Initialize or override the active context.
      # @param context [Context] the trace context to store in the active scope
      def context=(context)
        context.otel_thread_context = @otel_thread_context if context.respond_to?(:otel_thread_context=) # steep:ignore NoMethod

        if (otel_thread_context = @otel_thread_context)
          if (trace = context&.active_trace)
            otel_thread_context.update_from_trace_op(trace)
          else
            otel_thread_context.clear
          end
        end

        @context.current = context
      end

      # Return the active context for the configured scope.
      #
      # @param key [Object, nil] provide a custom object to fetch the active context from.
      #   DEV: Remove unused parameter `key`. It's never used, and makes the code complicate.
      #   DEV: All the `get_local_for` methods can be removed if we remove this parameter.
      # @return [Context, nil] the context for the active scope, or `nil` if none is set.
      def context(key = nil)
        current_context = key.nil? ? @context.current : @context.current(key)

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

    # A base class for context storage implementations.
    # It provides unique instance ID generation to ensure multiple scope instances
    # do not conflict with each other.
    #
    # @abstract
    class ContextScope
      def initialize(otel_thread_context: nil)
        @otel_thread_context = otel_thread_context
        @key = :"datadog_context_#{self.class.next_instance_id}"

        self.current = Context.new(otel_thread_context: otel_thread_context)
      end

      # Initialize or override the active context.
      # @param context [Context] the trace context to store in the active scope
      # @abstract
      def current=(context)
        raise NotImplementedError
      end

      # Return the active context.
      # @param storage [Object, nil] optional storage object to retrieve context from
      # @return [Context, nil] the context for the current or specified storage, or `nil` if none is set.
      def current(storage = nil)
        if storage
          get_current_for(storage)
        else
          get_current
        end
      end

      class << self
        def unique_instance_mutex
          @unique_instance_mutex ||= Mutex.new
        end

        def unique_instance_generator
          @unique_instance_generator ||= Datadog::Core::Utils::Sequence.new
        end

        # DEV: This is a very conservative way to ensure storage keys do not collide
        # DEV: when threads/fibers are resued. We can probably find something faster.
        def next_instance_id
          unique_instance_mutex.synchronize { unique_instance_generator.next }
        end
      end

      protected

      # Retrieve context from the current execution unit's storage.
      # @return [Context]
      # @abstract
      def get_current
        raise NotImplementedError
      end

      # Retrieve context from a specific storage object.
      # @param storage [Object] the storage object to retrieve context from
      # @return [Context]
      # @abstract
      def get_current_for(storage)
        raise NotImplementedError
      end
    end

    # Stores a different context for each Fiber.
    # There's no context inheritance between Fibers, as the
    # implementation is unrelated to `Fiber#storage`.
    #
    # @see https://ruby-doc.org/core-3.1.2/Thread.html#method-i-5B-5D Thread attributes are fiber-local
    class FiberIsolatedScope < ContextScope
      def current=(context)
        Thread.current[@key] = context
      end

      protected

      def get_current
        Thread.current[@key] ||= Context.new(otel_thread_context: @otel_thread_context)
      end

      def get_current_for(storage)
        storage[@key] ||= Context.new(otel_thread_context: @otel_thread_context)
      end
    end

    # Stores a different context for each Fiber, like {FiberIsolatedScope},
    # but a Fiber's new trace continues from the active trace of the Fiber that created it
    # (e.g. an `Enumerator` or an `Async` task), as a separate trace chunk.
    # Threads do not inherit the active trace.
    #
    # Requires `Fiber[]` (Ruby 3.2+).
    #
    # @see https://docs.ruby-lang.org/en/master/Fiber.html#class-Fiber-label-Fiber+Storage
    class FiberInheritedScope < FiberIsolatedScope
      def current=(context)
        # Ruby also copies Fiber storage into new Threads, so record the owner Thread.
        Fiber[@key] = [Thread.current, context].freeze
        super
      end

      protected

      def get_current
        Thread.current[@key] || (self.current = Context.new(otel_thread_context: @otel_thread_context, parent: inherited_context))
      end

      private

      def inherited_context
        thread, context = Fiber[@key]
        context if thread.equal?(Thread.current)
      end
    end
  end
end
