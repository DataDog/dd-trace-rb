# frozen_string_literal: true

module Datadog
  module Core
    module Runtime
      # @public_api
      module Ext
        TAG_ID = 'runtime-id'
        TAG_LANG = 'language'
        TAG_PROCESS_ID = 'process_id'

        # Metrics
        # @public_api
        module Metrics
          ENV_ENABLED = 'DD_RUNTIME_METRICS_ENABLED'

          METRIC_CLASS_COUNT = 'runtime.ruby.class_count'
          METRIC_GC_PREFIX = 'runtime.ruby.gc'
          METRIC_THREAD_COUNT = 'runtime.ruby.thread_count'
          METRIC_GLOBAL_CONSTANT_STATE = 'runtime.ruby.global_constant_state'
          METRIC_GLOBAL_METHOD_STATE = 'runtime.ruby.global_method_state'
          METRIC_CONSTANT_CACHE_INVALIDATIONS = 'runtime.ruby.constant_cache_invalidations'
          METRIC_CONSTANT_CACHE_MISSES = 'runtime.ruby.constant_cache_misses'

          TAG_SERVICE = 'service'
        end
      end
    end
  end
end
