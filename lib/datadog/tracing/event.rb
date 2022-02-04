# typed: false
require 'datadog/core'

module Datadog
  module Tracing
    # Event behavior and DSL
    module Events
      def self.included(base)
        base.extend(ClassMethods)
        base.include(InstanceMethods)
      end

      # Class methods
      module ClassMethods
        def build(**event_handlers)
          events = new
          events.subscribe(**event_handlers)
          events
        end
      end

      # Instance methods
      module InstanceMethods
        def subscribe(**event_handlers)
          return unless event_handlers

          event_handlers.each do |event_name, handlers|
            handlers.each do |handler_name, handler|
              events.send(event_name).subscribe(handler_name, &handler)
            end
          end

          event_handlers
        end
      end
    end

    # A simple pub-sub event model for components to exchange messages through.
    class Event
      attr_reader \
        :name,
        :subscriptions

      def initialize(name)
        @name = name
        @subscriptions = {}
        # @mutex = Mutex.new
      end

      def subscribe(key, &block)
        raise ArgumentError, 'Must give a block to subscribe!' unless block

        # @mutex.synchronize do
          subscriptions[key] = block
        # end
      end

      def wrap(key)
        raise ArgumentError, 'Must give a block to subscribe!' unless block_given?

        # @mutex.synchronize do
          original = subscriptions[key]

          subscriptions[key] = proc do |*args|
            yield(original, *args)
          end
        # end
      end

      def unsubscribe(key)
        # @mutex.synchronize do
          subscriptions.delete(key)
        # end
      end

      def unsubscribe_all!
        # @mutex.synchronize do
          subscriptions.clear
        # end

        true
      end

      def publish(*args)
        # @mutex.synchronize do
          subscriptions.each do |key, block|
            begin
              block.call(*args)
            rescue StandardError => e
              Datadog.logger.debug { "Error while handling '#{key}' for '#{name}' event: #{e.message}" }
            end
          end

          true
        # end
      end
    end
  end
end
