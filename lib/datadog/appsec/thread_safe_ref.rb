# frozen_string_literal: true

module Datadog
  module AppSec
    # This class is used for referencing an object that might be marked
    # for finalization in another thread.
    #
    # References to the object are counted, and objects marked for finalization
    # can be safely finalized when their reference count reaches zero.
    class ThreadSafeRef
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
