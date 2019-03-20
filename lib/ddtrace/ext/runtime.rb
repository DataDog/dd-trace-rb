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

      TAG_LANG = 'language'.freeze
      TAG_RUNTIME_ID = 'runtime-id'.freeze

      # Metrics
      module Metrics
        METRIC_CLASS_COUNT = 'runtime.ruby.class_count'.freeze
        METRIC_GC_PREFIX = 'runtime.ruby.gc'.freeze
        METRIC_THREAD_COUNT = 'runtime.ruby.thread_count'.freeze

        TAG_SERVICE = 'service'.freeze
      end
    end
  end
end
