# frozen_string_literal: true

module Datadog
  module DI
    # Per-thread execution-context generation token. A thread's ident can be
    # reused after the thread exits, so two snapshots sharing a thread_id are
    # not guaranteed to come from the same execution context. Pairing the id
    # with a generation token makes the ambiguity detectable: same id +
    # different generation means different threads.
    #
    # The token is a lazily assigned counter keyed by the Thread object (not
    # its ident): distinct Thread objects get distinct tokens even when their
    # idents collide. Tokens are unique only within a runtime id, which is
    # emitted alongside them in the snapshot envelope, so cross-process and
    # cross-fork uniqueness is handled by runtime_id.
    #
    # @api private
    module ThreadGeneration
      # @api private
      class State
        def initialize
          @generations = ObjectSpace::WeakMap.new
          @counter = 0
          @lock = Mutex.new
        end

        # Returns the generation token for the given thread.
        #
        # @param thread [Thread]
        # @return [Integer]
        def current(thread = Thread.current)
          @generations[thread] || @lock.synchronize do
            @generations[thread] || (@generations[thread] = (@counter += 1))
          end
        end
      end

      # Process-wide generation ledger. A constant holds the mutable state so
      # the module itself carries no singleton instance variables.
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
