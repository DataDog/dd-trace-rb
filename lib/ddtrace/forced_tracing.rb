require 'ddtrace/ext/forced_tracing'
require 'ddtrace/ext/priority'

module Datadog
  # Defines analytics behavior
  module ForcedTracing
    class << self
      def keep(span)
        return if span.nil? || span.context.nil?
        span.context.sampling_priority = Datadog::Ext::Priority::USER_KEEP
      end

      def drop(span)
        return if span.nil? || span.context.nil?
        span.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT
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
      # NOTE: This patching strategy only works because it has been applied after
      #       Datadog::Analytics::Span. Any changes will likely break this.
      module InstanceMethodsCompatibility
        def self.included(base)
          base.send(:alias_method, :set_tag_without_forced_tracing, :set_tag)

          define_method :set_tag do |*args, &block|
            set_tag_without_forced_tracing(*args, &block)
          end
        end
      end

      # Instance methods
      module InstanceMethods
        def set_tag(key, value)
          # Configure sampling priority if they give us a forced tracing tag
          # DEV: Do not set if the value they give us is explicitly "false"
          case key
          when Ext::ForcedTracing::TAG_KEEP
            ForcedTracing.keep(self) unless value == false
          when Ext::ForcedTracing::TAG_DROP
            ForcedTracing.drop(self) unless value == false
          else
            # Otherwise, set the tag normally.
            super if defined?(super)
          end
        end
      end
    end
  end
end
