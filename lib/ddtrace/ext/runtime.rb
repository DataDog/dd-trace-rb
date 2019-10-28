require 'ddtrace/version'

module Datadog
  module Ext
    module Runtime
      # Identity
      LANG = 'ruby'.freeze
      LANG_INTERPRETER = (RUBY_ENGINE + '-' + RUBY_PLATFORM).freeze
      LANG_VERSION = RUBY_VERSION
      TRACER_VERSION = Datadog::VERSION::STRING

      TAG_LANG = 'language'.freeze

      # Metrics
      module Metrics
        ENV_ENABLED = 'DD_RUNTIME_METRICS_ENABLED'.freeze

        METRIC_CLASS_COUNT = 'runtime.ruby.class_count'.freeze
        METRIC_GC_PREFIX = 'runtime.ruby.gc'.freeze
        METRIC_THREAD_COUNT = 'runtime.ruby.thread_count'.freeze

        TAG_SERVICE = 'service'.freeze
      end
    end
  end
end
