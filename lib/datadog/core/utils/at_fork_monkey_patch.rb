# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Monkey patches `Kernel#fork` and similar functions, adding an `at_fork` callback mechanism which
      # is used to restart observability after the VM forks (e.g. in multiprocess Ruby apps).
      module AtForkMonkeyPatch
        AT_FORK_BEFORE_BLOCKS = [] # rubocop:disable Style/MutableConstant -- Used to store blocks to run, mutable by design.
        private_constant :AT_FORK_BEFORE_BLOCKS

        AT_FORK_PARENT_BLOCKS = [] # rubocop:disable Style/MutableConstant -- Used to store blocks to run, mutable by design.
        private_constant :AT_FORK_PARENT_BLOCKS

        AT_FORK_CHILD_BLOCKS = [] # rubocop:disable Style/MutableConstant -- Used to store blocks to run, mutable by design.
        private_constant :AT_FORK_CHILD_BLOCKS

        def self.supported?
          Process.respond_to?(:fork)
        end

        def self.apply!
          return false unless supported?

          if RubyVersion.is?("< 3.1")
            [
              ::Process.singleton_class, # Process.fork
              ::Kernel.singleton_class,  # Kernel.fork
              ::Object,                  # fork without explicit receiver (it's defined as a method in ::Kernel)
              # Note: Modifying Object as we do here is irreversible. During tests, this
              # change will stick around even if we otherwise stub `Process` and `Kernel`
            ].each { |target| target.prepend(KernelMonkeyPatch) }
          end

          ::Process.singleton_class.prepend(ProcessMonkeyPatch)

          true
        end

        def self.run_at_fork_blocks(stage)
          blocks_for(stage).each(&:call)
        end

        # Registers a block to run at the given fork +stage+ (+:before+,
        # +:parent+, or +:child+).
        #
        # Returns the registered block so callers can keep a handle to it and
        # later deregister it via {.remove_at_fork}.
        def self.at_fork(stage, &block)
          raise(ArgumentError, "Missing block argument") unless block

          blocks_for(stage) << block

          block
        end

        # Deregisters a block previously registered with {.at_fork} for the given
        # +stage+. It is a no-op (does not raise) when +block+ was never
        # registered (or was already removed). Raises +ArgumentError+ for an
        # unknown stage, matching the {.at_fork} contract.
        def self.remove_at_fork(stage, block)
          blocks_for(stage).delete(block)

          nil
        end

        def self.blocks_for(stage)
          case stage
          when :before then AT_FORK_BEFORE_BLOCKS
          when :parent then AT_FORK_PARENT_BLOCKS
          when :child then AT_FORK_CHILD_BLOCKS
          else raise(ArgumentError, "Unsupported stage #{stage}")
          end
        end
        private_class_method :blocks_for

        # Adds `at_fork` behavior; see parent module for details.
        module KernelMonkeyPatch
          def fork
            # If a block is provided, it must be wrapped to trigger callbacks.
            child_block = if block_given?
              proc do
                AtForkMonkeyPatch.run_at_fork_blocks(:child)

                # Invoke original block
                yield
              end
            end

            # Run pre-fork callbacks in the parent, just before forking.
            AtForkMonkeyPatch.run_at_fork_blocks(:before)

            # Start fork
            # If a block is provided, use the wrapped version.
            begin
              result = child_block.nil? ? super : super(&child_block)
            rescue Exception # rubocop:disable Lint/RescueException -- re-raised unchanged; we only need to run parent cleanup first
              # The fork failed and we are still in the parent; run `:parent` to
              # restore any state the `:before` blocks set up, then re-raise.
              AtForkMonkeyPatch.run_at_fork_blocks(:parent)
              raise
            end

            # When fork gets called without a block, it returns twice:
            # If we're in the fork, result = nil: trigger child callbacks.
            # If we're in the parent, result = pid: trigger parent callbacks.
            # (If it gets called with a block, it only returns on the parent)
            if result.nil?
              AtForkMonkeyPatch.run_at_fork_blocks(:child)
            else
              AtForkMonkeyPatch.run_at_fork_blocks(:parent)
            end

            result
          end
        end

        # Adds `at_fork` behavior; see parent module for details.
        module ProcessMonkeyPatch
          # Hook provided by Ruby 3.1+ for observability libraries that want to know about fork, see
          # https://github.com/ruby/ruby/pull/5017 and https://bugs.ruby-lang.org/issues/17795
          def _fork
            AtForkMonkeyPatch.run_at_fork_blocks(:before)

            begin
              pid = super
            rescue Exception # rubocop:disable Lint/RescueException -- re-raised unchanged; we only need to run parent cleanup first
              # The fork failed, so no child was created and we are still in the
              # parent. The `:before` blocks already ran (and may hold resources,
              # e.g. a locked mutex); run the `:parent` blocks so that state is
              # restored, then re-raise.
              AtForkMonkeyPatch.run_at_fork_blocks(:parent)
              raise
            end

            if pid == 0
              AtForkMonkeyPatch.run_at_fork_blocks(:child)
            else
              AtForkMonkeyPatch.run_at_fork_blocks(:parent)
            end

            pid
          end

          # A call to Process.daemon ( https://rubyapi.org/3.1/o/process#method-c-daemon ) forks the current process and
          # keeps executing code in the child process, killing off the parent, thus effectively replacing it.
          # This is not covered by `_fork` and thus we have some extra code for it.
          def daemon(*args)
            AtForkMonkeyPatch.run_at_fork_blocks(:before)

            begin
              result = super
            rescue Exception # rubocop:disable Lint/RescueException -- re-raised unchanged; we only need to run parent cleanup first
              # `daemon` failed, so the original process survives; run `:parent`
              # to restore state the `:before` blocks set up, then re-raise.
              AtForkMonkeyPatch.run_at_fork_blocks(:parent)
              raise
            end

            # `daemon` kills the parent, so there is no surviving parent to run
            # `:parent` callbacks in; only the child continues executing.
            AtForkMonkeyPatch.run_at_fork_blocks(:child)

            result
          end
        end
      end
    end
  end
end
