# frozen_string_literal: true

require 'ddtrace/contrib/analytics'

module Datadog
  module Contrib
    module Que
      # Tracer is a Que's server-side middleware which traces executed jobs
      class Tracer
        def call(job)
          trace_options = {
            service:   configuration[:service_name],
            span_type: Datadog::Ext::AppTypes::WORKER,
            on_error: configuration[:error_handler]
          }

          tracer.trace(Ext::SPAN_JOB, trace_options) do |request_span|
            request_span.resource = job.class.name.to_s
            request_span.set_tag(Ext::TAG_JOB_QUEUE, job.que_attrs[:queue])
            request_span.set_tag(Ext::TAG_JOB_ID, job.que_attrs[:id])
            request_span.set_tag(Ext::TAG_JOB_PRIORITY, job.que_attrs[:priority])
            request_span.set_tag(Ext::TAG_JOB_ERROR_COUNT, job.que_attrs[:error_count])
            request_span.set_tag(Ext::TAG_JOB_RUN_AT, job.que_attrs[:run_at])
            request_span.set_tag(Ext::TAG_JOB_EXPIRED_AT, job.que_attrs[:expired_at])
            request_span.set_tag(Ext::TAG_JOB_FINISHED_AT, job.que_attrs[:finished_at])
            request_span.set_tag(Ext::TAG_JOB_ARGS, job.que_attrs[:args]) if configuration[:tag_args]
            request_span.set_tag(Ext::TAG_JOB_DATA, job.que_attrs[:data]) if configuration[:tag_data]

            set_sample_rate(request_span)
            Contrib::Analytics.set_measured(request_span)

            yield
          end
        end

        private

        def set_sample_rate(request_span)
          if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
            Contrib::Analytics.set_sample_rate(
              request_span,
              configuration[:analytics_sample_rate]
            )
          end
        end

        def tracer
          configuration[:tracer]
        end

        def configuration
          Datadog.configuration[Datadog::Contrib::Que::Ext::APP.to_sym]
        end
      end
    end
  end
end
