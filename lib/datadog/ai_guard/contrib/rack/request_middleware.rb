# frozen_string_literal: true

require_relative "../../../tracing/client_ip"
require_relative "../../../tracing/contrib/rack/header_collection"
require_relative "../../../tracing/metadata/ext"
require_relative "../../ext"

module Datadog
  module AIGuard
    module Contrib
      module Rack
        # AI Guard Rack middleware. Inserted just after
        # Datadog::Tracing::Contrib::Rack::TraceMiddleware so that, on the
        # way out of the request, the active span is the local root (request)
        # span. Tags `http.client_ip` and `network.client.ip` on that span
        # only when an AI Guard span was actually recorded during the request.
        class RequestMiddleware
          NETWORK_CLIENT_IP_TAG = "network.client.ip"

          def initialize(app, opt = {})
            @app = app
          end

          def call(env)
            @app.call(env)
          ensure
            tag_client_ip(env) if ai_guard_span_recorded?
          end

          private

          def ai_guard_span_recorded?
            trace = Datadog::Tracing.active_trace
            return false unless trace

            # `TraceOperation#@spans` has no reader; reaching for the ivar
            # avoids expanding the public API of tracing for one consumer.
            spans = trace.instance_variable_get(:@spans) || []
            spans.any? { |span| span.name == Datadog::AIGuard::Ext::SPAN_NAME }
          end

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
