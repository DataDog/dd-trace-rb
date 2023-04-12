module Datadog
  module Profiling
    # This module contains classes and methods which are implemented using native code in the
    # ext/ddtrace_profiling_native_extension folder, as well as some Ruby-level utilities that don't make sense to
    # write using C
    module NativeExtension
      private_class_method def self.working?
        native_working?
      end

      unless singleton_class.private_method_defined?(:native_working?)
        private_class_method def self.native_working?
          false
        end
      end

      unless singleton_class.method_defined?(:clock_id_for)
        def self.clock_id_for(_)
          nil
        end
      end

      def self.cpu_time_ns_for(thread)
        clock_id =
          begin
            clock_id_for(thread)
          rescue Errno::ESRCH
            nil
          end

        begin
          ::Process.clock_gettime(clock_id, :nanosecond) if clock_id
        rescue Errno::EINVAL
          nil
        end
      end
    end
  end
end
