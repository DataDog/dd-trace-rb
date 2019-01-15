require 'ddtrace/runtime/class_count'
require 'ddtrace/runtime/heap_size'
require 'ddtrace/runtime/thread_count'

module Datadog
  module Runtime
    # For generating runtime metrics
    module Metrics
      METRIC_CLASS_COUNT = 'datadog.tracer.runtime.class_count'.freeze
      METRIC_HEAP_SIZE = 'datadog.tracer.runtime.heap_size'.freeze
      METRIC_THREAD_COUNT = 'datadog.tracer.runtime.thread_count'.freeze

      module_function

      # Flush all runtime metrics to a Datadog::Metrics instance.
      def flush(metrics = Datadog.metrics)
        try_flush { metrics.gauge(METRIC_CLASS_COUNT, ClassCount.value) if ClassCount.available? }
        try_flush { metrics.gauge(METRIC_HEAP_SIZE, HeapSize.value) if HeapSize.available? }
        try_flush { metrics.gauge(METRIC_THREAD_COUNT, ThreadCount.value) if ThreadCount.available? }
      end

      def try_flush
        yield
      rescue StandardError => e
        Datadog::Tracer.log.error("Error while sending runtime metric. Cause: #{e.message}")
      end
    end
  end
end
