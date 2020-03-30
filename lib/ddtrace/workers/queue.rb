module Datadog
  module Workers
    # Adds queue behavior to workers, with a buffer
    # to which items can be queued then dequeued.
    module Queue
      def self.included(base)
        base.send(:prepend, PrependedMethods)
      end

      # Methods that must be prepended
      module PrependedMethods
        def perform(*args)
          super(*dequeue) if work_pending?
        end
      end

      def buffer
        @buffer ||= []
      end

      def enqueue(*args)
        buffer.push(args)
      end

      def dequeue
        buffer.shift
      end

      def work_pending?
        !buffer.empty?
      end

      protected

      attr_writer \
        :buffer
    end
  end
end
