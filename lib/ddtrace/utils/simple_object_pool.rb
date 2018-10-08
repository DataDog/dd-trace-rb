module Datadog
  module Utils
    # Basic bounded object pool implementation
    class SimpleObjectPool
      def initialize(size, &block)
        @size = size
        @count = 0
        @pool = []
        Queue.new
        @obj_builder = block
      end

      def checkout
        @pool.shift || build
      end

      def checkin(obj)
        @pool.unshift(obj)
      end

      def with
        obj = checkout
        yield(obj) if obj
      ensure
        checkin(obj) if obj
      end

      private

      def build
        return if @count >= @size

        @count += 1
        @obj_builder.call
      end
    end
  end
end

