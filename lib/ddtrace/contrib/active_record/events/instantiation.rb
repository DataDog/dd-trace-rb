require 'ddtrace/contrib/active_record/event'

module Datadog
  module Contrib
    module ActiveRecord
      module Events
        # Defines instrumentation for instantiation.active_record event
        module Instantiation
          include ActiveRecord::Event

          EVENT_NAME = 'instantiation.active_record'.freeze
          SPAN_NAME = 'active_record.instantiation'.freeze
          DEFAULT_SERVICE_NAME = 'active_record'.freeze

          module_function

          def supported?
            Gem.loaded_specs['activerecord'] \
              && Gem.loaded_specs['activerecord'].version >= Gem::Version.new('4.2')
          end

          def event_name
            self::EVENT_NAME
          end

          def span_name
            self::SPAN_NAME
          end

          def process(span, event, _id, payload)
            # Inherit service name from parent, if available.
            span.service = if configuration[:orm_service_name]
                             configuration[:orm_service_name]
                           elsif span.parent
                             span.parent.service
                           else
                             self::DEFAULT_SERVICE_NAME
                           end

            span.resource = payload.fetch(:class_name)
            span.span_type = 'custom'
            span.set_tag('active_record.instantiation.class_name', payload.fetch(:class_name))
            span.set_tag('active_record.instantiation.record_count', payload.fetch(:record_count))
          rescue StandardError => e
            Datadog::Tracer.log.debug(e.message)
          end
        end
      end
    end
  end
end
