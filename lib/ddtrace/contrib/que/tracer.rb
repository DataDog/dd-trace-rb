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
            span_type: Datadog::Ext::AppTypes::WORKER
          }
          request_span = tracer.trace(Ext::SPAN_JOB, trace_options)

          request_span.resource = job.class.name.to_s
          request_span.set_tag(Ext::TAG_JOB_QUEUE, job.que_attrs[:queue])
          request_span.set_tag(Ext::TAG_JOB_ID, job.que_attrs[:id])
          request_span.set_tag(Ext::TAG_JOB_ARGS, job.que_attrs[:args])
          request_span.set_tag(Ext::TAG_JOB_DATA, job.que_attrs[:data])
          request_span.set_tag(Ext::TAG_JOB_PRIORITY, job.que_attrs[:priority])
          request_span.set_tag(Ext::TAG_JOB_ERROR_COUNT, job.que_attrs[:error_count])
          request_span.set_tag(Ext::TAG_JOB_EXPIRED_AT, job.que_attrs[:expired_at])
          request_span.set_tag(Ext::TAG_JOB_FINISHED_AT, job.que_attrs[:finished_at])

          if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
            Contrib::Analytics.set_sample_rate(
              request_span,
              configuration[:analytics_sample_rate]
            )
          end

          Contrib::Analytics.set_measured(request_span)

          yield
        rescue StandardError => e
          request_span.set_error(e) unless request_span.nil?
          raise e
        ensure
          request_span.finish if request_span
        end

        private

        def tracer
          configuration[:tracer]
        end

        def configuration
          Datadog.configuration[:que]
        end
      end
    end
  end
end
