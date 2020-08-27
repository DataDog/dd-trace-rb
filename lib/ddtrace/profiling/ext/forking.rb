module Datadog
  module Profiling
    module Ext
      # Extensions for forking.
      module Forking
        def self.supported?
          RUBY_PLATFORM != 'java'
        end

        def self.apply!
          return false unless supported?

          modules = [::Process, ::Kernel]
          # TODO: Ruby < 2.3 doesn't support Binding#receiver.
          #       Remove "else #eval" clause when Ruby < 2.3 support is dropped.
          modules << (TOPLEVEL_BINDING.respond_to?(:receiver) ? TOPLEVEL_BINDING.receiver : TOPLEVEL_BINDING.eval('self'))

          # Patch top-level binding, Kernel, Process.
          # NOTE: We could instead do Kernel.module_eval { def fork; ... end }
          #       however, this method rewrite is more invasive and irreversible.
          #       It could also have collisions with other libraries that patch.
          #       Opt to modify the inheritance of each relevant target instead.
          modules.each do |mod|
            if mod.class <= Module
              mod.singleton_class.class_eval do
                prepend Kernel
              end
            else
              mod.extend(Kernel)
            end
          end
        end

        # Extensions for kernel
        module Kernel
          FORK_STAGES = [:prepare, :parent, :child].freeze

          def fork
            wrapped_block = proc do
              # Trigger :child callback
              at_fork_blocks[:child].each(&:call) if at_fork_blocks.key?(:child)
              yield
            end

            # Trigger :prepare callback
            at_fork_blocks[:prepare].each(&:call) if at_fork_blocks.key?(:prepare)

            # Start fork
            result = super(&wrapped_block)

            # Trigger :parent callback and return
            at_fork_blocks[:parent].each(&:call) if at_fork_blocks.key?(:parent)
            result
          end

          def at_fork(stage = :prepare, &block)
            raise ArgumentError, 'Bad \'stage\' for ::at_fork' unless FORK_STAGES.include?(stage)
            at_fork_blocks[stage] = [] unless at_fork_blocks.key?(stage)
            at_fork_blocks[stage] << block
          end

          module_function

          def at_fork_blocks
            # Blocks should be shared across all users of this module,
            # e.g. Process#fork, Kernel#fork, etc. should all invoke the same callbacks.
            # rubocop:disable Style/ClassVars
            @@at_fork_blocks ||= {}
          end
        end
      end
    end
  end
end
