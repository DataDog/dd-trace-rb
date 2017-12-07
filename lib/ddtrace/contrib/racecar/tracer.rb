module Datadog
  module Contrib
    module Racecar
      class Tracer
        NAME = 'racecar.consumer'.freeze

        def initialize(base)
          @base = base
        end

        def instrument(event_name, payload, &blk)
          unless instrumented_event?(event_name)
            return @base.instrument(event_name, payload, &blk)
          end

          Datadog.tracer.trace(NAME, service: service) do |span|
            span.resource = payload[:consumer_class]
            span.set_tag('kafka.topic', payload[:topic])
            span.set_tag('kafka.consumer', payload[:consumer_class])
            span.set_tag('kafka.partition', payload[:partition])
            span.set_tag('kafka.offset', payload[:offset]) if payload.key?(:offset)
            span.set_tag('kafka.first_offset', payload[:first_offset]) if payload.key?(:first_offset)

            @base.instrument(event_name, payload, &blk)
          end
        end

        def service
          Datadog.configuration[:racecar][:service_name]
        end

        def instrumented_event?(name)
          name == 'process_message.racecar' || name == 'process_batch.racecar'
        end
      end
    end
  end
end
