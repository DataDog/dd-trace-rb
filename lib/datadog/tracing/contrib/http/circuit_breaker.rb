require_relative '../../../../ddtrace/transport/ext'

module Datadog
  module Tracing
    module Contrib
      module HTTP
        # HTTP integration circuit breaker behavior
        # For avoiding recursive traces.
        module CircuitBreaker
          def should_skip_tracing?(request)
            return true if datadog_http_request?(request)

            # we don't want a "shotgun" effect with two nested traces for one
            # logical get, and request is likely to call itself recursively
            active = Tracing.active_span
            return true if active && (active.name == Ext::SPAN_REQUEST)

            false
          end

          # We don't want to trace our own call to the API (they use net/http)
          # TODO: We don't want this kind of soft-check on HTTP requests.
          #       Remove this when transport implements its own "skip tracing" mechanism.
          def datadog_http_request?(request)
            if request[Datadog::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION]
              true
            else
              false
            end
          end

          def should_skip_distributed_tracing?(client_config)
            return !client_config[:distributed_tracing] if client_config && client_config.key?(:distributed_tracing)

            !Datadog.configuration.tracing[:http][:distributed_tracing]
          end
        end
      end
    end
  end
end
