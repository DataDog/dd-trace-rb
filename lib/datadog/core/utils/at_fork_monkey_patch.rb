# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Monkey patches `Kernel#fork` and similar functions, adding an `at_fork` callback mechanism which
      # is used to restart observability after the VM forks (e.g. in multiprocess Ruby apps).
      module AtForkMonkeyPatch
        class Callback
          attr_reader :block, :group

          def initialize(block, group = nil)
            @block = block
            @group = group
            freeze
          end
        end
        private_constant :Callback

        EMPTY_AT_FORK_BLOCKS = {
          before: [].freeze,
          parent: [].freeze,
          child: [].freeze,
        }.freeze
        private_constant :EMPTY_AT_FORK_BLOCKS

        @at_fork_blocks = EMPTY_AT_FORK_BLOCKS

        # Serializes copy-on-write registry updates. Fork dispatch only reads the
        # latest immutable registry reference and never acquires this mutex.
        AT_FORK_REGISTRY_MUTEX = Mutex.new
        private_constant :AT_FORK_REGISTRY_MUTEX

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

        # Runs the callbacks copied for one fork lifecycle. Before callbacks
        # stop at the first failure; parent and child callbacks all run before
        # the first failure is re-raised.
        def self.run_at_fork_blocks(stage, snapshot:, started: nil)
          callbacks = blocks_for(snapshot, stage)
          if stage == :before
            return callbacks.each do |callback|
              started[callback.group] = true if started && callback.group
              callback.block.call
            end
          end

          error = nil
          callbacks.each do |callback|
            next if started && callback.group && !started.key?(callback.group)

            callback.block.call
          rescue Exception => e # rubocop:disable Lint/RescueException -- finish cleanup, then re-raise the first failure
            error ||= e
          end
          raise error if error
        end

        def self.run_parent_cleanup(snapshot, started, fork_error)
          run_at_fork_blocks(:parent, snapshot: snapshot, started: started)
        rescue Exception => cleanup_error # rubocop:disable Lint/RescueException -- preserve the original fork failure
          Datadog.logger.warn do
            "Parent at-fork cleanup failed while handling #{fork_error.class}: " \
              "#{cleanup_error.class}: #{cleanup_error.message}"
          end
        end
        private_class_method :run_parent_cleanup

        # Registers a block to run at the given fork +stage+ (+:before+,
        # +:parent+, or +:child+).
        #
        # Returns the registered block so callers can keep a handle to it and
        # later deregister it via {.remove_at_fork}.
        def self.at_fork(stage, &block)
          raise(ArgumentError, "Missing block argument") unless block

          AT_FORK_REGISTRY_MUTEX.synchronize do
            current = @at_fork_blocks
            @at_fork_blocks = current.merge(
              stage => (blocks_for(current, stage) + [Callback.new(block)]).freeze,
            ).freeze
          end

          block
        end

        # Registers one before/parent/child callback triplet atomically relative
        # to the snapshots taken by fork dispatch.
        def self.at_fork_blocks(before:, parent:, child:)
          blocks = {before: before, parent: parent, child: child}
          group = Object.new.freeze
          AT_FORK_REGISTRY_MUTEX.synchronize do
            current = @at_fork_blocks
            @at_fork_blocks = {
              before: (current.fetch(:before) + [Callback.new(before, group)]).freeze,
              parent: (current.fetch(:parent) + [Callback.new(parent, group)]).freeze,
              child: (current.fetch(:child) + [Callback.new(child, group)]).freeze,
            }.freeze
          end
          blocks
        end

        # Deregisters a block previously registered with {.at_fork} for the given
        # +stage+. It is a no-op (does not raise) when +block+ was never
        # registered (or was already removed). Raises +ArgumentError+ for an
        # unknown stage, matching the {.at_fork} contract.
        def self.remove_at_fork(stage, block)
          AT_FORK_REGISTRY_MUTEX.synchronize do
            current = @at_fork_blocks
            callbacks = blocks_for(current, stage)
            @at_fork_blocks = current.merge(
              stage => callbacks.reject { |callback| callback.block.equal?(block) }.freeze,
            ).freeze
          end

          nil
        end

        # Returns the immutable callback registry for one fork lifecycle.
        # Copy-on-write updates publish a new reference, so registrations made
        # afterwards apply only to the next lifecycle without locking this read.
        def self.snapshot_at_fork_blocks
          @at_fork_blocks
        end

        def self.replace_at_fork_blocks(snapshot)
          AT_FORK_REGISTRY_MUTEX.synchronize { @at_fork_blocks = snapshot }
        end
        private_class_method :replace_at_fork_blocks

        def self.blocks_for(snapshot, stage)
          case stage
          when :before, :parent, :child then snapshot.fetch(stage)
          else raise(ArgumentError, "Unsupported stage #{stage}")
          end
        end
        private_class_method :blocks_for

        # Adds `at_fork` behavior; see parent module for details.
        module KernelMonkeyPatch
          def fork
            snapshot = AtForkMonkeyPatch.snapshot_at_fork_blocks
            started = {}

            # If a block is provided, it must be wrapped to trigger callbacks.
            child_block = if block_given?
              proc do
                AtForkMonkeyPatch.run_at_fork_blocks(:child, snapshot: snapshot)

                # Invoke original block
                yield
              end
            end

            begin
              # Run pre-fork callbacks in the parent, just before forking.
              AtForkMonkeyPatch.run_at_fork_blocks(:before, snapshot: snapshot, started: started)

              # Start fork. If a block is provided, use the wrapped version.
              result = child_block.nil? ? super : super(&child_block)
            rescue Exception => e # rubocop:disable Lint/RescueException -- re-raised unchanged; we only need to run parent cleanup first
              # The fork or a before-fork callback failed and we are still in
              # the parent. Restore any state set up by earlier callbacks.
              AtForkMonkeyPatch.send(:run_parent_cleanup, snapshot, started, e)
              raise
            end

            # When fork gets called without a block, it returns twice:
            # If we're in the fork, result = nil: trigger child callbacks.
            # If we're in the parent, result = pid: trigger parent callbacks.
            # (If it gets called with a block, it only returns on the parent)
            if result.nil?
              AtForkMonkeyPatch.run_at_fork_blocks(:child, snapshot: snapshot)
            else
              AtForkMonkeyPatch.run_at_fork_blocks(:parent, snapshot: snapshot)
            end

            result
          end
        end

        # Adds `at_fork` behavior; see parent module for details.
        module ProcessMonkeyPatch
          # Hook provided by Ruby 3.1+ for observability libraries that want to know about fork, see
          # https://github.com/ruby/ruby/pull/5017 and https://bugs.ruby-lang.org/issues/17795
          def _fork
            snapshot = AtForkMonkeyPatch.snapshot_at_fork_blocks
            started = {}
            begin
              AtForkMonkeyPatch.run_at_fork_blocks(:before, snapshot: snapshot, started: started)
              pid = super
            rescue Exception => e # rubocop:disable Lint/RescueException -- re-raised unchanged; we only need to run parent cleanup first
              # The fork or a before-fork callback failed, so no child was
              # created. Restore state set up by any earlier callbacks.
              AtForkMonkeyPatch.send(:run_parent_cleanup, snapshot, started, e)
              raise
            end

            if pid == 0
              AtForkMonkeyPatch.run_at_fork_blocks(:child, snapshot: snapshot)
            else
              AtForkMonkeyPatch.run_at_fork_blocks(:parent, snapshot: snapshot)
            end

            pid
          end

          # A call to Process.daemon ( https://rubyapi.org/3.1/o/process#method-c-daemon ) forks the current process and
          # keeps executing code in the child process, killing off the parent, thus effectively replacing it.
          # This is not covered by `_fork` and thus we have some extra code for it.
          def daemon(*args)
            snapshot = AtForkMonkeyPatch.snapshot_at_fork_blocks
            started = {}
            begin
              AtForkMonkeyPatch.run_at_fork_blocks(:before, snapshot: snapshot, started: started)
              result = super
            rescue Exception => e # rubocop:disable Lint/RescueException -- re-raised unchanged; we only need to run parent cleanup first
              # `daemon` or a before-fork callback failed, so the original
              # process survives. Restore state set up by earlier callbacks.
              AtForkMonkeyPatch.send(:run_parent_cleanup, snapshot, started, e)
              raise
            end

            # `daemon` kills the parent, so there is no surviving parent to run
            # `:parent` callbacks in; only the child continues executing.
            AtForkMonkeyPatch.run_at_fork_blocks(:child, snapshot: snapshot)

            result
          end
        end
      end
    end
  end
end
