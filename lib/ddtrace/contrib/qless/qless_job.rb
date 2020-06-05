require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/analytics'
require 'qless'

module Datadog
  module Contrib
    module Qless
      # Uses Qless job hooks to create traces
      module QlessJob
        def around_perform(job)
          return super unless datadog_configuration && tracer
          tracer.trace(Ext::SPAN_JOB, span_options) do |span|
            span.resource = job.klass_name
            span.span_type = Datadog::Ext::AppTypes::WORKER
            # Set analytics sample rate
            if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(span)

            super
          end
        end

        def after_fork
          configuration = Datadog.configuration[:qless]
          return if configuration.nil?

          # Add a pin, marking the job as forked.
          # Used to trigger shutdown in forks for performance reasons.
          # Cleanup happens in the TracerCleaner class
          Datadog::Pin.new(
            configuration[:service_name],
            config: { forked: true }
          ).onto(::Qless)
        end

        private

        def span_options
          { service: datadog_configuration[:service_name] }
        end

        def tracer
          datadog_configuration.tracer
        end

        def datadog_configuration
          Datadog.configuration[:qless]
        end
      end
    end
  end
end
