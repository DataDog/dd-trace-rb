
module Datadog
  module Contrib
    module HTTP
      # HTTP integration circuit breaker behavior
      # For avoiding recursive traces.
      module CircuitBreaker
        def should_skip_tracing?(req, address, port, transport, pin)
          # we don't want to trace our own call to the API (they use net/http)
          # when we know the host & port (from the URI) we use it, else (most-likely
          # called with a block) rely on the URL at the end.
          if req.respond_to?(:uri) && req.uri
            if req.uri.host.to_s == transport.hostname.to_s &&
               req.uri.port.to_i == transport.port.to_i
              return true
            end
          elsif address && port &&
                address.to_s == transport.hostname.to_s &&
                port.to_i == transport.port.to_i
            return true
          end
          # we don't want a "shotgun" effect with two nested traces for one
          # logical get, and request is likely to call itself recursively
          active = pin.tracer.active_span
          return true if active && (active.name == Ext::SPAN_REQUEST)
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
