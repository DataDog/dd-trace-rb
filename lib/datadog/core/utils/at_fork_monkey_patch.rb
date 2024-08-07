# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Monkey patches `Kernel#fork` and similar functions, adding a `Process#datadog_at_fork` callback mechanism which
      # is used to restart observability after the VM forks (e.g. in multiprocess Ruby apps).
      module AtForkMonkeyPatch
        def self.supported?
          Process.respond_to?(:fork)
        end

        def self.apply!
          return false unless supported?

          if RUBY_VERSION < '3.1'
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

        # Adds `datadog_at_fork` behavior; see parent module for details.
        module KernelMonkeyPatch
          def fork
            # If a block is provided, it must be wrapped to trigger callbacks.
            child_block = if block_given?
                            proc do
                              # Trigger :child callback
                              datadog_at_fork_blocks[:child].each(&:call) if datadog_at_fork_blocks.key?(:child)

                              # Invoke original block
                              yield
                            end
                          end

            # Start fork
            # If a block is provided, use the wrapped version.
            result = child_block.nil? ? super : super(&child_block)

            # When fork gets called without a block, it returns twice:
            # If we're in the fork, result = nil: trigger child callbacks.
            # If we're in the parent, result = pid: we do nothing.
            # (If it gets called with a block, it only returns on the parent)
            datadog_at_fork_blocks[:child].each(&:call) if result.nil? && datadog_at_fork_blocks.key?(:child)

            result
          end

          module_function

          def datadog_at_fork_blocks
            # Blocks are shared across all users of this module,
            # e.g. Process#fork, Kernel#fork, etc. should all invoke the same callbacks.
            @@datadog_at_fork_blocks ||= {} # rubocop:disable Style/ClassVars
          end
        end

        # Adds `datadog_at_fork` behavior; see parent module for details.
        module ProcessMonkeyPatch
          # Hook provided by Ruby 3.1+ for observability libraries that want to know about fork, see
          # https://github.com/ruby/ruby/pull/5017 and https://bugs.ruby-lang.org/issues/17795
          def _fork
            datadog_at_fork_blocks = Datadog::Core::Utils::AtForkMonkeyPatch::KernelMonkeyPatch.datadog_at_fork_blocks

            pid = super

            datadog_at_fork_blocks[:child].each(&:call) if datadog_at_fork_blocks.key?(:child) && pid == 0

            pid
          end

          # A call to Process.daemon ( https://rubyapi.org/3.1/o/process#method-c-daemon ) forks the current process and
          # keeps executing code in the child process, killing off the parent, thus effectively replacing it.
          # This is not covered by `_fork` and thus we have some extra code for it.
          def daemon(*args)
            datadog_at_fork_blocks = Datadog::Core::Utils::AtForkMonkeyPatch::KernelMonkeyPatch.datadog_at_fork_blocks

            result = super

            datadog_at_fork_blocks[:child].each(&:call) if datadog_at_fork_blocks.key?(:child)

            result
          end

          # NOTE: You probably want to wrap any calls to datadog_at_fork with a OnlyOnce so as to not re-register
          #       the same block/behavior more than once.
          def datadog_at_fork(stage, &block)
            ProcessMonkeyPatch.datadog_at_fork(stage, &block)
          end

          # Also allow calling without going through Process for tests
          def self.datadog_at_fork(stage, &block)
            raise ArgumentError, 'Bad \'stage\' for ::datadog_at_fork' unless stage == :child

            datadog_at_fork_blocks = Datadog::Core::Utils::AtForkMonkeyPatch::KernelMonkeyPatch.datadog_at_fork_blocks
            datadog_at_fork_blocks[stage] ||= []
            datadog_at_fork_blocks[stage] << block

            nil
          end
        end
      end
    end
  end
end
