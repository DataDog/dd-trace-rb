require_relative '../core/buffer/thread_safe'
require_relative '../core/utils/object_set'
require_relative '../core/utils/string_table'

module Datadog
  module Profiling
    # Profiling buffer that stores profiling events. The buffer has a maximum size and when
    # the buffer is full, a random event is discarded. This class is thread-safe.
    class Buffer < Core::Buffer::ThreadSafe
      def initialize(*args)
        super
        @caches = {}
        @string_table = Core::Utils::StringTable.new
      end

      def cache(cache_name)
        synchronize do
          @caches[cache_name] ||= Core::Utils::ObjectSet.new
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
        @string_table = Core::Utils::StringTable.new

        items
      end
    end
  end
end
