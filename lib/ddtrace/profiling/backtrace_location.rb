module Datadog
  module Profiling
    # Entity class used to represent an entry in a stack trace.
    # Its fields are a simplified struct version of `Thread::Backtrace::Location`.
    class BacktraceLocation
      attr_reader \
        :base_label,
        :lineno,
        :path,
        :hash

      def initialize(
        base_label,
        lineno,
        path
      )
        @base_label = base_label
        @lineno = lineno
        @path = path
        @hash = [base_label, lineno, path].hash
      end

      def ==(other)
        hash == other.hash
      end

      def eql?(other)
        hash == other.hash
      end
    end
  end
end
