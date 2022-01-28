# typed: false
require 'datadog/tracing/metadata/ext'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/active_job/ext'
require 'ddtrace/contrib/active_job/event'

module Datadog
  module Contrib
    module ActiveJob
      module Events
        # Defines instrumentation for retry_stopped.active_job event
        module RetryStopped
          include ActiveJob::Event

          EVENT_NAME = 'retry_stopped.active_job'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_RETRY_STOPPED
          end

          def process(span, event, _id, payload)
            span.name = span_name
            span.service = configuration[:service_name] if configuration[:service_name]
            span.resource = payload[:job].class.name
            span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_RETRY_STOPPED)

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            set_common_tags(span, payload)
            span.set_tag(Ext::TAG_JOB_ERROR, payload[:error])
          rescue StandardError => e
            Datadog.logger.debug(e.message)
          end
        end
      end
    end
  end
end
