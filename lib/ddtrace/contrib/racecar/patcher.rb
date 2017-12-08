module Datadog
  module Contrib
    module Racecar
      # Provides instrumentation for `racecar` through ActiveSupport instrumentation signals
      module Patcher
        include Base
        NAME = 'racecar.consumer'.freeze
        register_as :racecar
        option :tracer, default: Datadog.tracer
        option :service_name, default: 'racecar'

        class << self
          def patch
            return patched? if patched? || !compatible?

            ::ActiveSupport::Notifications.subscribe('start_process_batch.racecar', &method(:start))
            ::ActiveSupport::Notifications.subscribe('start_process_message.racecar', &method(:start))
            ::ActiveSupport::Notifications.subscribe('process_batch.racecar', &method(:finish))
            ::ActiveSupport::Notifications.subscribe('process_message.racecar', &method(:finish))

            @patched = true
          end

          def patched?
            @patched ||= false
          end

          private

          def configuration
            Datadog.configuration[:racecar]
          end

          def compatible?
            defined?(::Racecar) && defined?(::ActiveSupport::Notifications)
          end

          def start(*_, payload)
            span = configuration[:tracer].trace(NAME)
            span.service = configuration[:service_name]
            span.resource = payload[:consumer_class]
            span.set_tag('kafka.topic', payload[:topic])
            span.set_tag('kafka.consumer', payload[:consumer_class])
            span.set_tag('kafka.partition', payload[:partition])
            span.set_tag('kafka.offset', payload[:offset]) if payload.key?(:offset)
            span.set_tag('kafka.first_offset', payload[:first_offset]) if payload.key?(:first_offset)

            payload.merge!(trace_span: span)
          end

          def finish(*_, payload)
            return unless payload[:trace_span]

            span = payload[:trace_span]
            span.set_error(payload[:exception_object]) if payload[:exception_object]
            span.finish
          end
        end
      end
    end
  end
end
