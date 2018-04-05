module Datadog
  module Contrib
    module ActiveSupport
      module Notifications
        # An ActiveSupport::Notification subscription that wraps events with tracing.
        class Subscription
          attr_reader \
            :tracer,
            :span_name,
            :options,
            :block

          def initialize(tracer, span_name, options, &block)
            raise ArgumentError, 'Must be given a block!' unless block_given?
            @tracer = tracer
            @span_name = span_name
            @options = options
            @block = block
            @before_trace_callbacks = []
            @after_trace_callbacks = []
          end

          def before_trace(&block)
            @before_trace_callbacks << block if block_given?
          end

          def after_trace(&block)
            @after_trace_callbacks << block if block_given?
          end

          def start(_name, _id, _payload)
            run_callbacks(@before_trace_callbacks)
            tracer.trace(@span_name, @options)
          end

          def finish(name, id, payload)
            tracer.active_span.tap do |span|
              return nil if span.nil?
              block.call(span, name, id, payload)
              span.finish
              run_callbacks(@after_trace_callbacks)
            end
          end

          def subscribe(pattern)
            return false if subscribers.key?(pattern)
            subscribers[pattern] = ::ActiveSupport::Notifications.subscribe(pattern, self)
            true
          end

          def unsubscribe(pattern)
            return false unless subscribers.key?(pattern)
            ::ActiveSupport::Notifications.unsubscribe(subscribers[pattern])
            subscribers.delete(pattern)
            true
          end

          def unsubscribe_all
            return false if subscribers.empty?
            subscribers.keys.each { |pattern| unsubscribe(pattern) }
            true
          end

          protected

          # Pattern => ActiveSupport:Notifications::Subscribers
          def subscribers
            @subscribers ||= {}
          end

          def run_callbacks(callbacks)
            callbacks.each do |callback|
              begin
                callback.call
              rescue StandardError => e
                Datadog::Tracer.log.debug("ActiveSupport::Notifications callback failed: #{e.message}")
              end
            end
          end
        end
      end
    end
  end
end
