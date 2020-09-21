module Datadog
  module Profiling
    # A simplified struct version of Thread::Backtrace::Location
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
