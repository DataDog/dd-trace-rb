# typed: false

require 'ddtrace/ext/metadata'

module Datadog
  module Contrib
    module ActionCable
      module Instrumentation
        # When a new WebSocket is open, we receive a Rack request resource name "GET -1".
        # This module overrides the current Rack resource name to provide a meaningful name.
        module ActionCableConnection
          def on_open
            Datadog::Tracing.trace(Ext::SPAN_ON_OPEN) do |span, trace|
              begin
                span.resource = "#{self.class}#on_open"
                span.span_type = Datadog::Ext::AppTypes::WEB

                span.set_tag(Ext::TAG_ACTION, 'on_open')
                span.set_tag(Ext::TAG_CONNECTION, self.class.to_s)

                span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
                span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_ON_OPEN)

                # Set the resource name of the trace
                trace.resource = span.resource
              rescue StandardError => e
                Datadog.logger.error("Error preparing span for ActionCable::Connection: #{e}")
              end

              super
            end
          end
        end

        # Instrumentation for when a Channel is subscribed to/unsubscribed from.
        module ActionCableChannel
          def self.included(base)
            base.class_eval do
              set_callback(
                :subscribe,
                :around,
                ->(channel, block) { Tracer.trace(channel, :subscribe, &block) },
                prepend: true
              )

              set_callback(
                :unsubscribe,
                :around,
                ->(channel, block) { Tracer.trace(channel, :unsubscribe, &block) },
                prepend: true
              )
            end
          end

          # Instrumentation for Channel hooks.
          class Tracer
            def self.trace(channel, hook)
              configuration = Datadog::Tracing.configuration[:action_cable]

              Datadog::Tracing.trace("action_cable.#{hook}") do |span|
                span.service = configuration[:service_name] if configuration[:service_name]
                span.resource = "#{channel.class}##{hook}"
                span.span_type = Datadog::Ext::AppTypes::WEB

                # Set analytics sample rate
                if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                  Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
                end

                # Measure service stats
                Contrib::Analytics.set_measured(span)

                span.set_tag(Ext::TAG_CHANNEL_CLASS, channel.class.to_s)

                span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
                span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, hook)

                yield
              end
            end
          end
        end
      end
    end
  end
end
