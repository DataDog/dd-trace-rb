# frozen_string_literal: true

module Datadog
  module Profiling
    module Ext
      # Monkey patches `Kernel#fork` and similar functions, adding a `Kernel#at_fork` callback mechanism which
      # is used to restart observability after the VM forks (e.g. in multiprocess Ruby apps).
      #
      # TODO: Use `Process._fork` on Ruby 3.1+, see
      #       https://github.com/ruby/ruby/pull/5017 and https://bugs.ruby-lang.org/issues/17795
      #
      # Known limitations: Does not handle `BasicObject`s that include `Kernel` directly; e.g.
      # `Class.new(BasicObject) { include(::Kernel); def call; fork { }; end }.new.call`.
      # This will be fixed once we move to hooking into `Process._fork`
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

          ::Process.singleton_class.prepend(ProcessDaemonPatch)
        end

        module Kernel
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

          def at_fork(stage, &block)
            raise ArgumentError, 'Bad \'stage\' for ::at_fork' unless stage == :child

            datadog_at_fork_blocks[stage] ||= []
            datadog_at_fork_blocks[stage] << block

            nil
          end

          module_function

          def datadog_at_fork_blocks
            # Blocks are shared across all users of this module,
            # e.g. Process#fork, Kernel#fork, etc. should all invoke the same callbacks.
            @@datadog_at_fork_blocks ||= {} # rubocop:disable Style/ClassVars
          end
        end

        # A call to Process.daemon ( https://rubyapi.org/3.1/o/process#method-c-daemon ) forks the current process and
        # keeps executing code in the child process, killing off the parent, thus effectively replacing it.
        #
        # This monkey patch makes the `Kernel#at_fork` mechanism defined above also work in this situation.
        module ProcessDaemonPatch
          def daemon(*args)
            datadog_at_fork_blocks = Datadog::Profiling::Ext::Forking::Kernel.datadog_at_fork_blocks

            result = super

            datadog_at_fork_blocks[:child].each(&:call) if datadog_at_fork_blocks.key?(:child)

            result
          end
        end
      end
    end
  end
end
