module Datadog
  module Contrib
    module ActionCable
      module Instrumentation
        # Instruments ActionCable::Connection to ensure the top-level
        # rack request has the correct resource for this WebSockets connection.
        #
        # Some of our common assumptions don't hold under WebSockets, one example
        # being the http status code, which is -1 for this request.
        module ActionCableConnection
          def on_open
            Datadog.tracer.trace('action_cable.on_open') do |span|
              begin
                span.resource = "#{self.class}#on_open"
                span.span_type = Datadog::Ext::AppTypes::WEB

                span.set_tag('action_cable.action', 'on_open')
                span.set_tag('action_cable.connection', self.class.to_s)

                # Set the resource name of the Rack request span
                rack_request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
                rack_request_span.resource = span.resource if rack_request_span
              rescue StandardError => e
                Datadog::Tracer.log.error("Error preparing span for ActionCable::Connection: #{e}")
              end

              super
            end
          end
        end
      end
    end
  end
end
