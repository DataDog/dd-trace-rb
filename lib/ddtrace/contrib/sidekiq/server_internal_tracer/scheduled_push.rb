# typed: true

module Datadog
  module Contrib
    module Sidekiq
      module ServerInternalTracer
        # Trace when Sidekiq checks to see if there are scheduled jobs that need to be worked
        # https://github.com/mperham/sidekiq/wiki/Scheduled-Jobs
        module ScheduledPush
          def enqueue
            configuration = Datadog.configuration[:sidekiq]

            Datadog.tracer.trace(Ext::SPAN_SCHEDULED_PUSH, service: configuration[:service_name]) do |span|
              span.span_type = Datadog::Ext::AppTypes::WORKER

              span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_SCHEDULED_PUSH)

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
