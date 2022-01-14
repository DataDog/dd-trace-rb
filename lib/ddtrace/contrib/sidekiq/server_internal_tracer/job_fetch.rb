# typed: true

module Datadog
  module Contrib
    module Sidekiq
      module ServerInternalTracer
        # Trace when Sidekiq looks for another job to work
        module JobFetch
          private

          def fetch
            configuration = Datadog.configuration[:sidekiq]

            configuration[:tracer].trace(Ext::SPAN_JOB_FETCH) do |span|
              span.service = configuration[:service_name]
              span.span_type = Datadog::Ext::AppTypes::WORKER

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                rate = configuration[:fetch_sample_rate] || configuration[:analytics_sample_rate]
                Contrib::Analytics.set_sample_rate(span, rate)
              end

              super
            end
          end
        end
      end
    end
  end
end
