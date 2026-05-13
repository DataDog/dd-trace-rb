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
        # At request entry the middleware computes the request attributes the
        # anomaly-detection pipeline needs (user agent, resolved client IP,
        # REMOTE_ADDR) and stashes them on the active trace under the
        # `_dd.ai_guard.` prefix. AI Guard evaluation reads the stash and
        # mirrors the values onto the AI Guard span. On the way out, the
        # middleware promotes the stashed IPs to the request span when AI
        # Guard ran during the request, then clears the stash so the
        # internal tags never reach the backend.
        #
        # TODO: remove the `steep:ignore` blocks below once
        # `Datadog::Tracing.active_trace` is signed correctly. It is signed
        # as `TraceSegment?` in `sig/datadog/tracing.rbs` but at runtime
        # returns a `TraceOperation`, which is what exposes `get_tag`,
        # `set_tag`, and `clear_tag`. Fixing the upstream sig is out of
        # scope for this PR.
        class RequestMiddleware
          NETWORK_CLIENT_IP_TAG = "network.client.ip"

          def initialize(app, opt = {})
            @app = app
          end

          def call(env)
            stash_request_attributes(env)

            @app.call(env)
          ensure
            tag_client_ip_on_request_span if consume_ai_guard_executed_flag
            clear_stash
          end

          private

          # Compute request attributes from the rack env and stash them on
          # the active trace under `_dd.ai_guard.<key>`. AI Guard evaluation
          # reads these to populate the AI Guard span; the ensure block reads
          # them again to tag the request span when AI Guard ran.
          # steep:ignore:start
          def stash_request_attributes(env)
            trace = Datadog::Tracing.active_trace
            return unless trace

            headers = Datadog::Tracing::Contrib::Rack::Header::RequestHeaderCollection.new(env)
            remote_ip = env["REMOTE_ADDR"]
            resolved_client_ip = Datadog::Tracing::ClientIp.extract_client_ip(headers, remote_ip)

            user_agent = env["HTTP_USER_AGENT"]
            trace.set_tag("#{Datadog::AIGuard::Ext::STASH_TAG_PREFIX}#{Datadog::AIGuard::Ext::HTTP_USERAGENT_TAG}", user_agent) if user_agent
            trace.set_tag("#{Datadog::AIGuard::Ext::STASH_TAG_PREFIX}#{Datadog::AIGuard::Ext::HTTP_CLIENT_IP_TAG}", resolved_client_ip) if resolved_client_ip
            trace.set_tag("#{Datadog::AIGuard::Ext::STASH_TAG_PREFIX}#{Datadog::AIGuard::Ext::NETWORK_CLIENT_IP_TAG}", remote_ip) if remote_ip
          rescue => e
            Datadog::AIGuard.telemetry&.report(e, description: "AI Guard: failed to stash request attributes")
          end
          # steep:ignore:end

          # AI Guard's evaluation flow sets `_dd.ai_guard.executed` on the
          # trace whenever an AI Guard span is created during the request.
          # We read it here to know whether to tag client IP, then clear it
          # so the internal flag does not propagate to the exported trace.
          # steep:ignore:start
          def consume_ai_guard_executed_flag
            trace = Datadog::Tracing.active_trace
            return false unless trace
            return false unless trace.get_tag(Datadog::AIGuard::Ext::SERVICE_ENTRY_EXECUTED_TAG) == "1"

            trace.clear_tag(Datadog::AIGuard::Ext::SERVICE_ENTRY_EXECUTED_TAG)
            true
          end

          def clear_stash
            trace = Datadog::Tracing.active_trace
            return unless trace

            Datadog::AIGuard::Ext::SERVICE_ENTRY_ATTRIBUTE_KEYS.each do |tag|
              trace.clear_tag("#{Datadog::AIGuard::Ext::STASH_TAG_PREFIX}#{tag}")
            end
          end
          # steep:ignore:end

          # steep:ignore:start
          def tag_client_ip_on_request_span
            span = Datadog::Tracing.active_span
            return unless span

            trace = Datadog::Tracing.active_trace
            return unless trace

            client_ip = trace.get_tag("#{Datadog::AIGuard::Ext::STASH_TAG_PREFIX}#{Datadog::AIGuard::Ext::HTTP_CLIENT_IP_TAG}")
            if client_ip && span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP).nil?
              span.set_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, client_ip)
            end

            network_client_ip = trace.get_tag("#{Datadog::AIGuard::Ext::STASH_TAG_PREFIX}#{Datadog::AIGuard::Ext::NETWORK_CLIENT_IP_TAG}")
            if network_client_ip && span.get_tag(NETWORK_CLIENT_IP_TAG).nil?
              span.set_tag(NETWORK_CLIENT_IP_TAG, network_client_ip)
            end
          rescue => e
            Datadog::AIGuard.telemetry&.report(e, description: "AI Guard: failed to tag client IP on root span")
          end
          # steep:ignore:end
        end
      end
    end
  end
end
