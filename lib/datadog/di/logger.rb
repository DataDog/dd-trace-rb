# frozen_string_literal: true

require 'forwardable'

module Datadog
  module DI
    # Logger facade to add the +trace+ method.
    #
    # @api private
    class Logger
      extend Forwardable

      def initialize(settings, target)
        @settings = settings
        @target = target
      end

      attr_reader :settings
      attr_reader :target

      def_delegators :target, :debug

      def trace(&block)
        if settings.dynamic_instrumentation.internal.trace_logging
          debug(&block)
        end
      end
    end
  end
end
