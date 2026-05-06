# frozen_string_literal: true

require_relative "../../../tracing/client_ip"
require_relative "../../../tracing/contrib/rack/header_collection"
require_relative "../../../tracing/metadata/ext"
require_relative "../../ext"

module Datadog
  module AIGuard
    module Contrib
      module Rack
        # AI Guard Rack middleware.
        #
        # Inserted into the middleware stack right after
        # Datadog::Tracing::Contrib::Rack::TraceMiddleware (i.e. nested inside
        # it). This ordering matters: on the way out of the request, AI Guard's
        # `ensure` block unwinds *before* Tracing's ensure, while Tracing's
        # request span is still live. We need that, because Tracing's ensure
        # calls `request_span.finish`, which builds a frozen `Span` snapshot of
        # the meta hash — any `set_tag` call after that point mutates the
        # `SpanOperation` but never reaches the exported `Span`.
        #
        # So while the span is still active, we tag `http.client_ip` and
        # `network.client.ip` on it — but only when an AI Guard span was
        # actually recorded during the request.
        class RequestMiddleware
          NETWORK_CLIENT_IP_TAG = "network.client.ip"

          def initialize(app, opt = {})
            @app = app
          end

          def call(env)
            @app.call(env)
          ensure
            tag_client_ip(env) if consume_ai_guard_executed_flag
          end

          private

          # AI Guard's evaluation flow sets `ai_guard.executed` on the trace
          # whenever an AI Guard span is created during the request. We read
          # it here to know whether to tag client IP, then clear it so the
          # internal flag does not propagate to the exported trace.
          #
          # `Tracing.active_trace` is publicly typed as `TraceSegment?` but at
          # runtime returns a `TraceOperation`, which exposes `get_tag` and
          # `clear_tag`. Pre-existing sig mismatch — hence the steep:ignore.
          # steep:ignore:start
          def consume_ai_guard_executed_flag
            trace = Datadog::Tracing.active_trace
            return false unless trace
            return false unless trace.get_tag(Datadog::AIGuard::Ext::SERVICE_ENTRY_EXECUTED_TAG) == "1"

            trace.clear_tag(Datadog::AIGuard::Ext::SERVICE_ENTRY_EXECUTED_TAG)
            true
          end
          # steep:ignore:end

          def tag_client_ip(env)
            span = Datadog::Tracing.active_span
            return unless span

            if span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP).nil?
              headers = Datadog::Tracing::Contrib::Rack::Header::RequestHeaderCollection.new(env)
              Datadog::Tracing::ClientIp.set_client_ip_tag!(
                span,
                headers: headers,
                remote_ip: env["REMOTE_ADDR"]
              )
            end

            if env["REMOTE_ADDR"] && span.get_tag(NETWORK_CLIENT_IP_TAG).nil?
              span.set_tag(NETWORK_CLIENT_IP_TAG, env["REMOTE_ADDR"])
            end
          rescue StandardError => e # standard:disable Style/RescueStandardError
            Datadog::AIGuard.telemetry&.report(e, description: "AI Guard: failed to tag client IP on root span")
          end
        end
      end
    end
  end
end
