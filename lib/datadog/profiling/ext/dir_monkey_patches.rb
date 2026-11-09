# frozen_string_literal: true

module Datadog
  module Profiling
    # Monkey patches needed for profiler features and compatibility
    module Ext
      # Ruby versions before 3.4 have bugs in the `Dir` class implementation, causing issues such as
      # https://github.com/DataDog/dd-trace-rb/issues/3450 .
      # This was fixed upstream in https://bugs.ruby-lang.org/issues/20586 but we use this monkey patch to work around
      # the issue on legacy versions (it gets applied by `Datadog::Profiling::Component`).
      #
      # This monkey patch for the Ruby `Dir` class works around these bugs for affected Ruby versions by temporarily
      # blocking the profiler from interrupting system calls.
      #
      # A lot of these APIs do very similar things -- they're provided by Ruby as helpers so users don't need to keep
      # reimplementing them but share the same underlying buggy code. And so our monkey patches are a bit repetitive
      # as well.
      # We don't DRY out this file to have minimal overhead.
      #
      # These monkey patches are applied by the profiler when the "dir_interruption_workaround_enabled" setting is
      # enabled. See the profiling settings for more detail.
      module DirMonkeyPatches
        def self.apply!
          ::Dir.singleton_class.prepend(Datadog::Profiling::Ext::DirClassMonkeyPatches)
          ::Dir.prepend(Datadog::Profiling::Ext::DirInstanceMonkeyPatches)

          true
        end
      end

      # Monkey patches for Dir.singleton_class. See DirMonkeyPatches above for more details.
      module DirClassMonkeyPatches
        # Steep: Workaround that defines args, kwargs and block.
        # @type var args: ::Array[any]
        # @type var kwargs: ::Hash[::Symbol, any]
        # @type var block: ^(?) -> any | nil

        def [](...)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end

        def children(...)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end

        # See note on methods that yield above.
        def each_child(*args, **kwargs, &block)
          if block
            begin
              # <-- Begin critical region
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              super do |entry_name|
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
                # <-- We're safe now while running customer code
                yield entry_name
                # <-- We'll go back to the Dir internals, critical region again
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              end
            ensure
              # <-- End critical region
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
            end
          else
            # This returns an enumerator. We don't want/need to intercede here, the enumerator will eventually call the
            # other branch once it gets going.
            super
          end
        end

        def empty?(...)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end

        def entries(...)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end

        # See note on methods that yield above.
        def foreach(*args, **kwargs, &block)
          if block
            begin
              # <-- Begin critical region
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              super do |entry_name|
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
                # <-- We're safe now while running customer code
                yield entry_name
                # <-- We'll go back to the Dir internals, critical region again
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              end
            ensure
              # <-- End critical region
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
            end
          else
            # This returns an enumerator. We don't want/need to intercede here, the enumerator will eventually call the
            # other branch once it gets going.
            super
          end
        end

        # See note on methods that yield above.
        def glob(*args, **kwargs, &block)
          if block
            begin
              # <-- Begin critical region
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              super do |entry_name|
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
                # <-- We're safe now while running customer code
                yield entry_name
                # <-- We'll go back to the Dir internals, critical region again
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              end
            ensure
              # <-- End critical region
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
            end
          else
            begin
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              super
            ensure
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
            end
          end
        end

        def home(...)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end
      end

      # Monkey patches for Dir. See DirMonkeyPatches above for more details.
      module DirInstanceMonkeyPatches
        # Steep: Workaround that defines args, kwargs and block.
        # @type var args: ::Array[any]
        # @type var kwargs: ::Hash[::Symbol, any]
        # @type var block: ^(?) -> any | nil

        # See note on methods that yield above.
        def each(*args, **kwargs, &block)
          if block
            begin
              # <-- Begin critical region
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              super do |entry_name|
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
                # <-- We're safe now while running customer code
                yield entry_name
                # <-- We'll go back to the Dir internals, critical region again
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              end
            ensure
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals # <-- End critical region
            end
          else
            # This returns an enumerator. We don't want/need to intercede here, the enumerator will eventually call the
            # other branch once it gets going.
            super
          end
        end

        # See note on methods that yield above.
        def each_child(*args, **kwargs, &block)
          if block
            begin
              # <-- Begin critical region
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              super do |entry_name|
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
                # <-- We're safe now while running customer code
                yield entry_name
                # <-- We'll go back to the Dir internals, critical region again
                Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
              end
            ensure
              # <-- End critical region
              Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
            end
          else
            # This returns an enumerator. We don't want/need to intercede here, the enumerator will eventually call the
            # other branch once it gets going.
            super
          end
        end

        def children(...)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end

        def tell(...)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end

        def pos(...)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end
      end
    end
  end
end
