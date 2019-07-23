module Datadog
  module Contrib
    module HTTP
      # HTTP integration circuit breaker behavior
      # For avoiding recursive traces.
      module CircuitBreaker
        def should_skip_tracing?(req, address, port, tracer)
          return true if datadog_http_request?(req, address, port, tracer)

          # we don't want a "shotgun" effect with two nested traces for one
          # logical get, and request is likely to call itself recursively
          active = tracer.active_span
          return true if active && (active.name == Ext::SPAN_REQUEST)

          false
        end

        # We don't want to trace our own call to the API (they use net/http)
        # TODO: We don't want this kind of coupling with the transport.
        #       Remove this when transport implements its own "skip tracing" mechanism.
        def datadog_http_request?(req, address, port, tracer)
          transport = tracer.writer.transport

          transport_hostname = nil
          transport_port = nil

          # Get settings from transport, if available.
          case transport
          when Datadog::Transport::HTTP::Client
            adapter = transport.current_api.adapter
            if adapter.is_a?(Datadog::Transport::HTTP::Adapters::Net)
              transport_hostname = adapter.hostname.to_s
              transport_port = adapter.port.to_i
            end
          end

          # When we know the host & port (from the URI) we use it, else (most-likely
          # called with a block) rely on the URL at the end.
          if req.respond_to?(:uri) && req.uri
            if req.uri.host.to_s == transport_hostname &&
               req.uri.port.to_i == transport_port
              return true
            end
          elsif address && port &&
                address.to_s == transport_hostname &&
                port.to_i == transport_port
            return true
          end

          false
        end

        def should_skip_distributed_tracing?(pin)
          if pin.config && pin.config.key?(:distributed_tracing)
            return !pin.config[:distributed_tracing]
          end

          !Datadog.configuration[:http][:distributed_tracing]
        end
      end
    end
  end
end
