require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/active_record/ext'
require 'ddtrace/contrib/active_record/event'

module Datadog
  module Contrib
    module ActiveRecord
      module Events
        # Defines instrumentation for instantiation.active_record event
        module Instantiation
          include ActiveRecord::Event

          EVENT_NAME = 'instantiation.active_record'.freeze

          module_function

          def supported?
            Gem.loaded_specs['activerecord'] \
              && Gem.loaded_specs['activerecord'].version >= Gem::Version.new('4.2')
          end

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_INSTANTIATION
          end

          def process(span, event, _id, payload)
            # Inherit service name from parent, if available.
            span.service = if configuration[:orm_service_name]
                             configuration[:orm_service_name]
                           elsif span.parent
                             span.parent.service
                           else
                             Ext::SERVICE_NAME
                           end

            span.resource = payload.fetch(:class_name)
            span.span_type = Ext::SPAN_TYPE_INSTANTIATION

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            span.set_tag(Ext::TAG_INSTANTIATION_CLASS_NAME, payload.fetch(:class_name))
            span.set_tag(Ext::TAG_INSTANTIATION_RECORD_COUNT, payload.fetch(:record_count))
          rescue StandardError => e
            Datadog::Tracer.log.debug(e.message)
          end
        end
      end
    end
  end
end
