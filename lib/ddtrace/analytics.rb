require 'ddtrace/ext/analytics'

module Datadog
  # Defines analytics behavior
  module Analytics
    class << self
      def set_sample_rate(span, sample_rate)
        return if span.nil? || !sample_rate.is_a?(Numeric)
        span.set_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE, sample_rate)
      end
    end

    # Extension for Datadog::Span
    module Span
      def self.included(base)
        if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
          base.class_eval do
            # Instance methods
            include InstanceMethodsCompatibility
            include InstanceMethods
          end
        else
          base.send(:prepend, InstanceMethods)
        end
      end

      # Compatibility shim for Rubies not supporting `.prepend`
      module InstanceMethodsCompatibility
        def self.included(base)
          base.class_eval do
            alias_method :set_tag_without_analytics, :set_tag
            # DEV: When we stack multiple extensions the method might already be removed
            remove_method :set_tag if method_defined?(:set_tag)
          end
        end

        def set_tag(*args, &block)
          set_tag_without_analytics(*args, &block)
        end
      end

      # Instance methods
      module InstanceMethods
        def set_tag(key, value)
          case key
          when Ext::Analytics::TAG_ENABLED
            # If true, set rate to 1.0, otherwise set 0.0.
            value = value == true ? Ext::Analytics::DEFAULT_SAMPLE_RATE : 0.0
            Analytics.set_sample_rate(self, value)
          when Ext::Analytics::TAG_SAMPLE_RATE
            Analytics.set_sample_rate(self, value)
          else
            super if defined?(super)
          end
        end
      end
    end
  end
end
