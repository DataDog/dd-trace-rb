module Datadog
  module Contrib
    module ActionCable
      module Instrumentation
        # When a new WebSocket is open, we receive a Rack request resource name "GET -1".
        # This module overrides the current Rack resource name to provide a meaningful name.
        module ActionCableConnection
          def on_open
            Datadog.tracer.trace(Ext::SPAN_ON_OPEN) do |span|
              begin
                span.resource = "#{self.class}#on_open"
                span.span_type = Datadog::Ext::AppTypes::WEB

                span.set_tag(Ext::TAG_ACTION, 'on_open')
                span.set_tag(Ext::TAG_CONNECTION, self.class.to_s)

                # Set the resource name of the Rack request span
                rack_request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
                rack_request_span.resource = span.resource if rack_request_span
              rescue StandardError => e
                Datadog.logger.error("Error preparing span for ActionCable::Connection: #{e}")
              end

              super
            end
          end
        end
      end
    end
  end
end
