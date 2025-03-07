# frozen_string_literal: true

require_relative '../../../core/transport/ext'

module Datadog
  module Tracing
    module Contrib
      module HTTP
        # HTTP integration circuit breaker behavior
        # For avoiding recursive traces.
        module CircuitBreaker
          def should_skip_tracing?(request)
            return true if internal_request?(request)

            # we don't want a "shotgun" effect with two nested traces for one
            # logical get, and request is likely to call itself recursively
            active = Tracing.active_span
            return true if active && (active.name == Ext::SPAN_REQUEST)

            false
          end

          # We don't want to trace our own call to the API (they use net/http)
          # TODO: We don't want this kind of soft-check on HTTP requests.
          #       Remove this when transport implements its own "skip tracing" mechanism.
          def internal_request?(request)
            !!(request[Datadog::Core::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION] ||
              request[Datadog::Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST])
          end

          # Skips distributed tracing if disabled for this instrumentation
          # or if APM is disabled unless there is an AppSec event (from upstream distributed trace or local)
          def should_skip_distributed_tracing?(client_config, trace)
            if Datadog.configuration.appsec.standalone.enabled
              return true unless trace && trace.get_tag(Datadog::AppSec::Ext::TAG_DISTRIBUTED_APPSEC_EVENT) == '1'
            end

            return !client_config[:distributed_tracing] if client_config && client_config.key?(:distributed_tracing)

            !Datadog.configuration.tracing[:http][:distributed_tracing]
          end
        end
      end
    end
  end
end
