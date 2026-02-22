# frozen_string_literal: true

require_relative '../core/utils/sequence'
require_relative 'context'

module Datadog
  module Tracing
    # A concurrency-safe repository for storing and retrieving the current trace context.
    class DefaultContextProvider
      # @param scope [ContextScope] the scope to use for context storage.
      #   The scope defines the lifecycle of the context.
      def initialize(scope: FiberIsolatedScope.new)
        @context = scope
      end

      # Initialize or override the active context.
      # @param context [Context] the trace context to store in the active scope
      def context=(context)
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
      def initialize
        @key = :"datadog_context_#{self.class.next_instance_id}"

        self.current = Context.new
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

    # Stores context using thread-local variables, which are shared
    # across all Fibers running on the same Thread.
    #
    # @see https://ruby-doc.org/core-3.1.2/Thread.html#method-i-thread_variable_get
    class ThreadScope < ContextScope
      def current=(context)
        Thread.current.thread_variable_set(@key, context)
      end

      protected

      def get_current
        Thread.current.thread_variable_get(@key) || (self.current = Context.new)
      end

      def get_current_for(thread)
        context = thread.thread_variable_get(@key)
        return context if context

        context = Context.new
        thread.thread_variable_set(@key, context)
        context
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
        Thread.current[@key] ||= Context.new
      end

      def get_current_for(storage)
        storage[@key] ||= Context.new
      end
    end
  end
end
