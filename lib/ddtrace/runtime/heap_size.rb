module Datadog
  module Runtime
    # Retrieves heap size (in bytes) from runtime
    module HeapSize
      module_function

      def value
        GC.stat[:heap_allocated_pages] * 40 * 408
      end

      def available?
        GC.stat.key?(:heap_allocated_pages)
      end
    end
  end
end
