# frozen_string_literal: true

module Datadog
  module Profiling
    module Ext
      # All Ruby versions as of this writing have bugs in the dir class implementation, causing issues such as
      # https://github.com/DataDog/dd-trace-rb/issues/3450 .
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
        def [](*args, &block)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end
        ruby2_keywords :[] if respond_to?(:ruby2_keywords, true)

        def children(*args, &block)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end
        ruby2_keywords :children if respond_to?(:ruby2_keywords, true)

        def each_child(*args, &block)
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
        ruby2_keywords :each_child if respond_to?(:ruby2_keywords, true)

        def empty?(*args, &block)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end
        ruby2_keywords :empty? if respond_to?(:ruby2_keywords, true)

        def entries(*args, &block)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end
        ruby2_keywords :entries if respond_to?(:ruby2_keywords, true)

        def foreach(*args, &block)
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
        ruby2_keywords :foreach if respond_to?(:ruby2_keywords, true)

        def glob(*args, &block)
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
        ruby2_keywords :glob if respond_to?(:ruby2_keywords, true)

        def home(*args, &block)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end
        ruby2_keywords :home if respond_to?(:ruby2_keywords, true)
      end

      # Monkey patches for Dir. See DirMonkeyPatches above for more details.
      module DirInstanceMonkeyPatches
        def each(*args, &block)
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
        ruby2_keywords :each if respond_to?(:ruby2_keywords, true)

        unless RUBY_VERSION.start_with?('2.5.') # This is Ruby 2.6+
          def each_child(*args, &block)
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
          ruby2_keywords :each_child if respond_to?(:ruby2_keywords, true)

          def children(*args, &block)
            Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
            super
          ensure
            Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
          end
          ruby2_keywords :children if respond_to?(:ruby2_keywords, true)
        end

        def tell(*args, &block)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end
        ruby2_keywords :tell if respond_to?(:ruby2_keywords, true)

        def pos(*args, &block)
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_hold_signals
          super
        ensure
          Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_resume_signals
        end
        ruby2_keywords :pos if respond_to?(:ruby2_keywords, true)
      end
    end
  end
end
