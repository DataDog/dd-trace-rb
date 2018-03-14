module Datadog
  module Contrib
    module ActiveSupport
      class Notifications
        def self.subscribe(pattern, span_name, options = {}, tracer = Datadog.tracer, &block)
          subscriber = Subscriber.new(tracer, span_name, options, &block)

          ::ActiveSupport::Notifications.subscribe(pattern, subscriber)
        end

        class Subscriber
          def initialize(tracer, span_name, options, &block)
            @tracer = tracer
            @span_name = span_name
            @options = options
            @block = block

            # A stack of open spans. We want to get to the most recently opened span
            # at any point in time.
            @spans = []
          end

          def start(_name, _id, _payload)
            @spans << @tracer.trace(@span_name, @options)
          end

          def finish(name, id, payload)
            # We close spans in reverse order.
            span = @spans.pop or raise "no spans left in stack!"

            # The subscriber block needs to remember to set the name of the span.
            @block.call(span, name, id, payload)

            span.finish
          end
        end
      end
    end
  end
end
