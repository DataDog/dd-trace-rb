require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    module Racecar
      # Provides instrumentation for `racecar` through ActiveSupport instrumentation signals
      module Patcher
        include Base
        NAME_MESSAGE = 'racecar.message'.freeze
        NAME_BATCH = 'racecar.batch'.freeze
        register_as :racecar
        option :tracer, default: Datadog.tracer
        option :service_name, default: 'racecar'

        class << self
          def patch
            return patched? if patched? || !compatible?

            ::ActiveSupport::Notifications.subscribe('process_batch.racecar', self)
            ::ActiveSupport::Notifications.subscribe('process_message.racecar', self)

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

          def start(event, _, payload)
            ensure_clean_context!

            name = event[/message/] ? NAME_MESSAGE : NAME_BATCH
            span = configuration[:tracer].trace(name)
            span.service = configuration[:service_name]
            span.resource = payload[:consumer_class]
            span.set_tag('kafka.topic', payload[:topic])
            span.set_tag('kafka.consumer', payload[:consumer_class])
            span.set_tag('kafka.partition', payload[:partition])
            span.set_tag('kafka.offset', payload[:offset]) if payload.key?(:offset)
            span.set_tag('kafka.first_offset', payload[:first_offset]) if payload.key?(:first_offset)
            span.set_tag('kafka.message_count', payload[:message_count]) if payload.key?(:message_count)
          end

          def finish(_, _, payload)
            current_span = configuration[:tracer].call_context.current_span

            return unless current_span

            current_span.set_error(payload[:exception_object]) if payload[:exception_object]
            current_span.finish
          end

          private

          def configuration
            Datadog.configuration[:racecar]
          end

          def compatible?
            defined?(::Racecar) && defined?(::ActiveSupport::Notifications)
          end

          def ensure_clean_context!
            return unless configuration[:tracer].call_context.current_span

            configuration[:tracer].provider.context = Context.new
          end
        end
      end
    end
  end
end
