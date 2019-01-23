require 'ddtrace/version'

module Datadog
  module Ext
    module Runtime
      # Identity
      LANG = 'ruby'.freeze
      LANG_INTERPRETER = begin
        if Gem::Version.new(RUBY_VERSION) > Gem::Version.new('1.9')
          (RUBY_ENGINE + '-' + RUBY_PLATFORM)
        else
          ('ruby-' + RUBY_PLATFORM)
        end
      end.freeze
      LANG_VERSION = RUBY_VERSION
      TRACER_VERSION = Datadog::VERSION::STRING

      # Metrics
      METRIC_CLASS_COUNT = 'datadog.tracer.runtime.class_count'.freeze
      METRIC_HEAP_SIZE = 'datadog.tracer.runtime.heap_size'.freeze
      METRIC_THREAD_COUNT = 'datadog.tracer.runtime.thread_count'.freeze
    end
  end
end
