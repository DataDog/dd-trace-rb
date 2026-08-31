# frozen_string_literal: true

module Datadog
  module Profiling
    module Ext
      # The profiler gathers data by sending `SIGPROF` unix signals to Ruby application threads.
      #
      # When using `Kernel#exec` on Linux, it can happen that a signal sent before calling `exec` arrives after
      # the new process is running, causing it to fail with the `Profiling timer expired` error message.
      # To avoid this, the profiler installs a monkey patch on `Kernel#exec` to stop profiling before actually
      # calling `exec`.
      # This monkey patch is available for Ruby 2.7+; let us know if you need it on earlier Rubies.
      # For more details see https://github.com/DataDog/dd-trace-rb/issues/5101 .
      module ExecMonkeyPatch
        def self.apply!
          ::Object.prepend(ObjectMonkeyPatch)

          true
        end

        module ObjectMonkeyPatch
          private

          def exec(...)
            Datadog.send(:components, allow_initialization: false)&.profiler&.shutdown!(report_last_profile: false)
            super
          end
        end
      end
    end
  end
end
