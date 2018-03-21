require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/active_support/notifications/subscriber'

module Datadog
  module Contrib
    module Racecar
      # Provides instrumentation for `racecar` through ActiveSupport instrumentation signals
      module Patcher
        include Base
        include ActiveSupport::Notifications::Subscriber

        NAME_MESSAGE = 'racecar.message'.freeze
        NAME_BATCH = 'racecar.batch'.freeze
        register_as :racecar
        option :tracer, default: Datadog.tracer
        option :service_name, default: 'racecar'

        on_subscribe do
          subscribe('process_message.racecar', self::NAME_MESSAGE, {}, configuration[:tracer], &method(:process))
          subscribe('process_batch.racecar', self::NAME_BATCH, {}, configuration[:tracer], &method(:process))
        end

        class << self
          def patch
            return patched? if patched? || !compatible?

            subscribe!
            configuration[:tracer].set_service_info(
              configuration[:service_name],
              'racecar',
              Ext::AppTypes::WORKER
            )

            @patched = true
          end

          def patched?
            return @patched if defined?(@patched)
            @patched = false
          end

          def process(span, event, _, payload)
            span.service = configuration[:service_name]
            span.resource = payload[:consumer_class]

            span.set_tag('kafka.topic', payload[:topic])
            span.set_tag('kafka.consumer', payload[:consumer_class])
            span.set_tag('kafka.partition', payload[:partition])
            span.set_tag('kafka.offset', payload[:offset]) if payload.key?(:offset)
            span.set_tag('kafka.first_offset', payload[:first_offset]) if payload.key?(:first_offset)
            span.set_tag('kafka.message_count', payload[:message_count]) if payload.key?(:message_count)
            span.set_error(payload[:exception_object]) if payload[:exception_object]
          end

          private

          def configuration
            Datadog.configuration[:racecar]
          end

          def compatible?
            defined?(::Racecar) && defined?(::ActiveSupport::Notifications)
          end
        end
      end
    end
  end
end
