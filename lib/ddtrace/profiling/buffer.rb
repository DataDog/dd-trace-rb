require 'ddtrace/buffer'
require 'ddtrace/utils/string_table'
require 'ddtrace/utils/object_set'

module Datadog
  module Profiling
    # Profiling buffer that stores profiling events. The buffer has a maximum size and when
    # the buffer is full, a random event is discarded. This class is thread-safe.
    class Buffer < Datadog::ThreadSafeBuffer
      def initialize(*args)
        super
        @caches = {}
        @string_table = Utils::StringTable.new
      end

      def cache(cache_name)
        synchronize do
          @caches[cache_name] ||= Utils::ObjectSet.new
        end
      end

      def string_table
        synchronize do
          @string_table
        end
      end

      protected

      def drain!
        items = super

        # Clear caches
        @caches = {}
        @string_table = Utils::StringTable.new

        items
      end
    end
  end
end
