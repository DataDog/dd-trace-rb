# frozen_string_literal: true

module Datadog
  module DI
    # Per-thread execution-context generation token. A thread's ident can be
    # reused after the thread exits, so two snapshots sharing a thread_id are
    # not guaranteed to come from the same execution context. Pairing the id
    # with a generation token makes the ambiguity detectable: same id +
    # different generation means different threads.
    #
    # The token is a lazily assigned counter stored as a thread-local on the
    # Thread object: distinct Thread objects get distinct tokens even when
    # their idents collide. The token is reclaimed when the thread is garbage
    # collected, since it lives in the thread's own variable table. Tokens are
    # unique only within a runtime id, which is emitted alongside them in the
    # snapshot envelope, so cross-process and cross-fork uniqueness is handled
    # by runtime_id.
    #
    # @api private
    module ThreadGeneration
      # @api private
      class State
        # Thread-local key for each thread's generation token.
        THREAD_KEY = :datadog_di_thread_generation

        def initialize
          @counter = 0
          @lock = Mutex.new
        end

        # Returns the generation token for the given thread.
        #
        # @param thread [Thread]
        # @return [Integer]
        def current(thread = Thread.current)
          thread.thread_variable_get(THREAD_KEY) || @lock.synchronize do
            thread.thread_variable_get(THREAD_KEY) || thread.thread_variable_set(THREAD_KEY, @counter += 1)
          end
        end
      end

      # Process-wide generation ledger. The mutable state lives in a constant.
      STATE = State.new

      # Returns the generation token for the current thread.
      #
      # @return [Integer]
      def self.current
        STATE.current
      end
    end
  end
end
