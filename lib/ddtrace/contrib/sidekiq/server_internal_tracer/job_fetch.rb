# typed: true

module Datadog
  module Contrib
    module Sidekiq
      module ServerInternalTracer
        # Trace when Sidekiq looks for another job to work
        module JobFetch
          private

          def fetch
            configuration = Datadog::Tracing.configuration[:sidekiq]

            Datadog::Tracing.trace(Ext::SPAN_JOB_FETCH, service: configuration[:service_name]) do |span|
              span.span_type = Datadog::Ext::AppTypes::WORKER

              span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_JOB_FETCH)

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end

              super
            end
          end
        end
      end
    end
  end
end
