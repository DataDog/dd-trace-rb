require 'ddtrace/contrib/analytics'

require 'datadog/ci/ext/app_types'
require 'datadog/ci/ext/test'

module Datadog
  module CI
    # Common behavior for CI tests
    module Test
      # Creates a new span for a CI test
      def self.trace(tracer, span_name, options = {})
        span_options = {
          span_type: Ext::AppTypes::TEST
        }.merge(options[:span_options] || {})

        if block_given?
          tracer.trace(span_name, span_options) do |span|
            set_tags!(span, options)
            yield(span)
          end
        else
          span = tracer.trace(span_name, span_options)
          set_tags!(span, options)
          span
        end
      end

      # Adds tags to a CI test span.
      def self.set_tags!(span, tags = {})
        tags ||= {}

        # Set default tags
        Datadog::Contrib::Analytics.set_measured(span)
        span.set_tag(Ext::Test::TAG_SPAN_KIND, Ext::AppTypes::TEST)
        Ext::Environment.tags(ENV).each { |k, v| span.set_tag(k, v) }

        # Set contextual tags
        span.set_tag(Ext::Test::TAG_FRAMEWORK, tags[:framework]) if tags[:framework]
        span.set_tag(Ext::Test::TAG_NAME, tags[:test_name]) if tags[:test_name]
        span.set_tag(Ext::Test::TAG_SUITE, tags[:test_suite]) if tags[:test_suite]
        span.set_tag(Ext::Test::TAG_TYPE, tags[:test_type]) if tags[:test_type]

        span
      end

      def self.passed!(span)
        span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::PASS)
      end

      def self.failed!(span, exception = nil)
        span.status = 1
        span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::FAIL)
        span.set_error(exception) unless exception.nil?
      end

      def self.skipped!(span, exception = nil)
        span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::SKIP)
        span.set_error(exception) unless exception.nil?
      end
    end
  end
end
