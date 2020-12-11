# frozen_string_literal: true

require 'ddtrace/contrib/analytics'

module Datadog
  module Contrib
    module Sneakers
      # Tracer is a Sneakers server-side middleware which traces executed jobs
      class Tracer
        def initialize(app, *args)
          @app = app
          @args = args
        end

        def call(deserialized_msg, delivery_info, metadata, handler)
          trace_options = {
            service:   configuration[:service_name],
            span_type: Datadog::Ext::AppTypes::WORKER,
            on_error: configuration[:error_handler]
          }

          tracer.trace(Ext::SPAN_JOB, trace_options) do |request_span|
            # Set analytics sample rate
            if Datadog::Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Datadog::Contrib::Analytics.set_sample_rate(request_span, configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(request_span)

            request_span.resource = @app.to_proc.binding.eval('self.class').to_s
            request_span.set_tag(Ext::TAG_JOB_ROUTING_KEY, delivery_info.routing_key)
            request_span.set_tag(Ext::TAG_JOB_QUEUE, delivery_info.consumer.queue.name)

            if configuration[:tag_body]
              request_span.set_tag(Ext::TAG_JOB_BODY, deserialized_msg)
            end

            @app.call(deserialized_msg, delivery_info, metadata, handler)
          end
        end

        private

        def tracer
          configuration[:tracer]
        end

        def configuration
          Datadog.configuration[:sneakers]
        end
      end
    end
  end
end
