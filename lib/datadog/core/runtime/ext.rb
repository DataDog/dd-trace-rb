module Datadog
  module Core
    module Runtime
      # @public_api
      module Ext
        TAG_ID = 'runtime-id'.freeze
        TAG_LANG = 'language'.freeze
        TAG_PROCESS_ID = 'process_id'.freeze

        # Metrics
        # @public_api
        module Metrics
          ENV_ENABLED = 'DD_RUNTIME_METRICS_ENABLED'.freeze

          METRIC_CLASS_COUNT = 'runtime.ruby.class_count'.freeze
          METRIC_GC_PREFIX = 'runtime.ruby.gc'.freeze
          METRIC_THREAD_COUNT = 'runtime.ruby.thread_count'.freeze
          METRIC_GLOBAL_CONSTANT_STATE = 'runtime.ruby.global_constant_state'.freeze
          METRIC_GLOBAL_METHOD_STATE = 'runtime.ruby.global_method_state'.freeze
          METRIC_CONSTANT_CACHE_INVALIDATIONS = 'runtime.ruby.constant_cache_invalidations'.freeze
          METRIC_CONSTANT_CACHE_MISSES = 'runtime.ruby.constant_cache_misses'.freeze

          TAG_SERVICE = 'service'.freeze
        end
      end
    end
  end
end
