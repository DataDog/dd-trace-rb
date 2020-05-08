module Datadog
  module Contrib
    module HTTP
      # HTTP integration circuit breaker behavior
      # For avoiding recursive traces.
      module CircuitBreaker
        def should_skip_tracing?(request, tracer)
          return true if datadog_http_request?(request)

          # we don't want a "shotgun" effect with two nested traces for one
          # logical get, and request is likely to call itself recursively
          active = tracer.active_span
          return true if active && (active.name == Ext::SPAN_REQUEST)

          false
        end

        # We don't want to trace our own call to the API (they use net/http)
        # TODO: We don't want this kind of soft-check on HTTP requests.
        #       Remove this when transport implements its own "skip tracing" mechanism.
        def datadog_http_request?(request)
          if request[Datadog::Ext::Transport::HTTP::HEADER_META_TRACER_VERSION]
            true
          else
            false
          end
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
