require 'active_support/notifications'

module Datadog
  module Contrib
    module ActiveSupport
      module Notifications
        # An ActiveSupport::Notification subscription that wraps events with tracing.
        class Subscription
          attr_reader \
            :tracer,
            :span_name,
            :options

          def initialize(tracer, span_name, options, &block)
            raise ArgumentError, 'Must be given a block!' unless block_given?
            @tracer = tracer
            @span_name = span_name
            @options = options
            @block = block
          end

          def start(_name, _id, _payload)
            ensure_clean_context!
            tracer.trace(@span_name, @options)
          end

          def finish(name, id, payload)
            span = tracer.active_span

            # The subscriber block needs to remember to set the name of the span.
            @block.call(span, name, id, payload)

            span.finish
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

          private

          def ensure_clean_context!
            return unless tracer.call_context.current_span
            tracer.provider.context = Context.new
          end
        end
      end
    end
  end
end
