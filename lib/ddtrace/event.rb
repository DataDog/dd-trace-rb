require 'ddtrace/logger'

module Datadog
  # A simple pub-sub event model for components to exchange messages through.
  class Event
    attr_reader \
      :name,
      :subscriptions

    def initialize(name)
      @name = name
      @subscriptions = {}
      @mutex = Mutex.new
    end

    def subscribe(key, &block)
      raise ArgumentError, 'Must give a block to subscribe!' unless block

      @mutex.synchronize do
        subscriptions[key] = block
      end
    end

    def unsubscribe(key)
      @mutex.synchronize do
        subscriptions.delete(key)
      end
    end

    def unsubscribe_all!
      @mutex.synchronize do
        subscriptions.clear
      end

      true
    end

    def publish(*args)
      @mutex.synchronize do
        subscriptions.each do |key, block|
          begin
            block.call(*args)
          rescue StandardError => e
            Datadog::Logger.log.debug("Error while handling '#{key}' for '#{name}' event: #{e.message}")
          end
        end

        true
      end
    end
  end
end
