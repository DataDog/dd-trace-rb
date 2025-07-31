# frozen_string_literal: true

module Datadog
  module AppSec
    # This class is used for counting references to objects.
    # It might be useful when we need to substitute one object with another
    # and finalize the previous one in a thread-safe manner.
    class FinalizableRef
      def initialize(initial_obj, finalizer: :finalize!)
        @current = initial_obj
        @finalizer = finalizer

        @counters = Hash.new(0)
        @outdated = []
        @mutex = Mutex.new
      end

      def acquire
        @mutex.synchronize do
          @counters[@current] += 1

          @current
        end
      end

      def release(obj)
        @mutex.synchronize do
          @counters[obj] -= 1

          @outdated.reject! do |outdated_obj|
            next unless @counters[outdated_obj].zero?

            finalize(outdated_obj)
          end
        end
      end

      def current=(obj)
        @mutex.synchronize do
          @outdated << @current

          @current = obj
        end
      end

      private

      def finalize(obj)
        obj.public_send(@finalizer)

        true
      rescue => e
        Datadog.logger.debug("Couldn't finalize #{obj.class.name} object, error: #{e.inspect}")

        true
      end
    end
  end
end
