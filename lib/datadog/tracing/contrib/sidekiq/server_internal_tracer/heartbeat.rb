# typed: true

module Datadog
  module Tracing
    module Contrib
      module Sidekiq
        module ServerInternalTracer
          # Trace when a Sidekiq process has a heartbeat
          module Heartbeat
            def stop
              configuration = Datadog.configuration.tracing[:sidekiq]

              Datadog::Tracing.trace(Ext::SPAN_STOP, service: configuration[:service_name]) do |span|
                span.span_type = Datadog::Tracing::Metadata::Ext::AppTypes::TYPE_WORKER

                span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
                span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_STOP)

                # Set analytics sample rate
                if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                  Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
                end

                super
              end
            end

            private

            def beat
              configuration = Datadog.configuration.tracing[:sidekiq]

              Datadog::Tracing.trace(Ext::SPAN_HEARTBEAT, service: configuration[:service_name]) do |span|
                span.span_type = Datadog::Tracing::Metadata::Ext::AppTypes::TYPE_WORKER

                span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
                span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HEARTBEAT)

                # Set analytics sample rate
                if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                  Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
                end

                super
              end
            end

            # Provides an alias for the pre-v7.0.1 heartbeat method, which does the same thing as
            # the current Sidekiq::Launcher#beat method.
            alias heartbeat beat
          end
        end
      end
    end
  end
end
