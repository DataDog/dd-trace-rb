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

            configuration[:tracer].trace(Ext::SPAN_SCHEDULED_PUSH) do |span|
              span.service = configuration[:service_name]
              span.span_type = Datadog::Ext::AppTypes::WORKER

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
