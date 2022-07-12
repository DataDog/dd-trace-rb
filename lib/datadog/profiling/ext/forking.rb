# typed: false

module Datadog
  module Profiling
    module Ext
      # Monkey patches `Kernel#fork`, adding a `Kernel#at_fork` callback mechanism which is used to restore
      # profiling abilities after the VM forks.
      module Forking
        def self.supported?
          Process.respond_to?(:fork)
        end

        def self.apply!
          return false unless supported?

          [
            ::Process.singleton_class, # Process.fork
            ::Kernel.singleton_class,  # Kernel.fork
            ::Object,                  # fork without explicit receiver (it's defined as a method in ::Kernel)
            # Note: Modifying Object as we do here is irreversible. During tests, this
            # change will stick around even if we otherwise stub `Process` and `Kernel`
          ].each { |target| target.prepend(Kernel) }
        end

        # Extensions for kernel
        module Kernel
          FORK_STAGES = [:prepare, :parent, :child].freeze

          def fork
            # If a block is provided, it must be wrapped to trigger callbacks.
            child_block = if block_given?
                            proc do
                              # Trigger :child callback
                              ddtrace_at_fork_blocks[:child].each(&:call) if ddtrace_at_fork_blocks.key?(:child)

                              # Invoke original block
                              yield
                            end
                          end

            # Trigger :prepare callback
            ddtrace_at_fork_blocks[:prepare].each(&:call) if ddtrace_at_fork_blocks.key?(:prepare)

            # Start fork
            # If a block is provided, use the wrapped version.
            result = child_block.nil? ? super : super(&child_block)

            # Trigger correct callbacks depending on whether we're in the parent or child.
            # If we're in the fork, result = nil: trigger child callbacks.
            # If we're in the parent, result = fork PID: trigger parent callbacks.
            # rubocop:disable Style/IfInsideElse
            if result.nil?
              # Trigger :child callback
              ddtrace_at_fork_blocks[:child].each(&:call) if ddtrace_at_fork_blocks.key?(:child)
            else
              # Trigger :parent callback
              ddtrace_at_fork_blocks[:parent].each(&:call) if ddtrace_at_fork_blocks.key?(:parent)
            end
            # rubocop:enable Style/IfInsideElse

            # Return PID from #fork
            result
          end

          def at_fork(stage = :prepare, &block)
            raise ArgumentError, 'Bad \'stage\' for ::at_fork' unless FORK_STAGES.include?(stage)

            ddtrace_at_fork_blocks[stage] = [] unless ddtrace_at_fork_blocks.key?(stage)
            ddtrace_at_fork_blocks[stage] << block
          end

          module_function

          def ddtrace_at_fork_blocks
            # Blocks should be shared across all users of this module,
            # e.g. Process#fork, Kernel#fork, etc. should all invoke the same callbacks.
            # rubocop:disable Style/ClassVars
            @@ddtrace_at_fork_blocks ||= {}
            # rubocop:enable Style/ClassVars
          end
        end
      end
    end
  end
end
