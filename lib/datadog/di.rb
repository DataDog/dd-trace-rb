# frozen_string_literal: true

require_relative 'di/configuration'
require_relative 'di/extensions'
require_relative 'di/remote'

module Datadog
  # Namespace for Datadog dynamic instrumentation.
  #
  # @api private
  module DI
    INSTRUMENTED_COUNTERS_LOCK = Mutex.new

    class << self
      def enabled?
        Datadog.configuration.dynamic_instrumentation.enabled
      end

      # This method is called from DI Remote handler to issue DI operations
      # to the probe manager (add or remove probes).
      #
      # When DI Remote is executing, Datadog.components should be initialized
      # and we should be able to reference it to get to the DI component.
      #
      # Given that we need the current_component anyway for code tracker,
      # perhaps we should delete the +component+ method and just use
      # +current_component+ in all cases.
      def component
        Datadog.send(:components).dynamic_instrumentation
      end

      # Track how many outstanding instrumentations are in DI.
      #
      # It is hard to find the actual instrumentations - there is no
      # method provided by Ruby to list all trace points, and we would
      # need to manually track our instrumentation modules for method probes.
      # Plus, tracking the modules could create active references to
      # instrumentation, which is not desired.
      #
      # A simpler solution is to maintain a counter which is increased
      # whenever a probe is installed and decreased when a probe is removed.
      #
      # This counter does not include pending probes - being not installed,
      # those pose no concerns to customer applications.
      def instrumented_count(kind = nil)
        INSTRUMENTED_COUNTERS_LOCK.synchronize do
          if defined?(@instrumented_count)
            if kind
              validate_kind!(kind)
              @instrumented_count[kind] || 0
            else
              @instrumented_count.inject(0) do |sum, (kind, count)|
                sum + count
              end
            end
          else
            0
          end
        end
      end

      def instrumented_count_inc(kind)
        validate_kind!(kind)
        INSTRUMENTED_COUNTERS_LOCK.synchronize do
          @instrumented_count = Hash.new(0) unless defined?(@instrumented_count)
          @instrumented_count[kind] += 1
        end
      end

      def instrumented_count_dec(kind)
        validate_kind!(kind)
        INSTRUMENTED_COUNTERS_LOCK.synchronize do
          @instrumented_count = Hash.new(0) unless defined?(@instrumented_count)
          if @instrumented_count[kind] <= 0
            Datadog.logger.debug { "di: attempting to decrease instrumented count below zero for #{kind}" }
            return
          end
          @instrumented_count[kind] -= 1
        end
      end

      private def validate_kind!(kind)
        unless %i[line method].include?(kind)
          raise ArgumentError, "Invalid kind: #{kind}"
        end
      end
    end

    # Expose DI to global shared objects
    Extensions.activate!
  end
end
