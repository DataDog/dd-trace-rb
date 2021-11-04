# typed: true

module Datadog
  module Contrib
    module Sidekiq
      module ServerInternalTracer
        # Trace when a Sidekiq process has a heartbeat
        module Heartbeat
          private

          def ❤ # rubocop:disable Naming/AsciiIdentifiers, Naming/MethodName
            configuration = Datadog.configuration[:sidekiq]

            configuration[:tracer].trace(Ext::SPAN_HEARTBEAT) do |span|
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
