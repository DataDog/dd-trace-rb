# typed: true
require 'ddtrace/version'

module Datadog
  module Ext
    module Runtime
      TAG_ID = 'runtime-id'.freeze
      TAG_LANG = 'language'.freeze
      TAG_PID = 'system.pid'.freeze

      # Metrics
      module Metrics
        ENV_ENABLED = 'DD_RUNTIME_METRICS_ENABLED'.freeze

        METRIC_CLASS_COUNT = 'runtime.ruby.class_count'.freeze
        METRIC_GC_PREFIX = 'runtime.ruby.gc'.freeze
        METRIC_THREAD_COUNT = 'runtime.ruby.thread_count'.freeze
        METRIC_GLOBAL_CONSTANT_STATE = 'runtime.ruby.global_constant_state'.freeze
        METRIC_GLOBAL_METHOD_STATE = 'runtime.ruby.global_method_state'.freeze

        TAG_SERVICE = 'service'.freeze
      end
    end
  end
end
