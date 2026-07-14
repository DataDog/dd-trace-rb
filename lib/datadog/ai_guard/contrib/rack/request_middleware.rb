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
        # At request entry the middleware stores some request attributes for
        # on the active trace under the `_dd.ai_guard.` prefix.
        #
        # Later when AI Guard evaluation is performed, those attributes are
        # mirrored on AI Guard span.
        class RequestMiddleware
          def initialize(app, opt = {})
            @app = app
          end

          def call(env)
            trace = Datadog::Tracing.active_trace
            return @app.call(env) unless trace

            store_anomaly_detection_tags!(trace, env)

            @app.call(env)
          ensure
            # @type var trace: Datadog::Tracing::TraceSegment?
            # Steep: https://github.com/soutaro/steep/issues/919
            if trace
              tag_client_ip_on_request_span!(trace) if ai_guard_executed?(trace)

              clean_up_ai_guard_temp_tags!(trace)
            end
          end

          private

          # steep:ignore:start
          def store_anomaly_detection_tags!(trace, env)
            remote_ip = env["REMOTE_ADDR"]
            trace.set_tag(Datadog::AIGuard::Ext::TRACE_NETWORK_CLIENT_IP_TAG, remote_ip) if remote_ip

            headers = Datadog::Tracing::Contrib::Rack::Header::RequestHeaderCollection.new(env)
            resolved_client_ip = Datadog::Tracing::ClientIp.extract_client_ip(headers, remote_ip)
            trace.set_tag(Datadog::AIGuard::Ext::TRACE_HTTP_CLIENT_IP_TAG, resolved_client_ip) if resolved_client_ip

            user_agent = env["HTTP_USER_AGENT"]
            trace.set_tag(Datadog::AIGuard::Ext::TRACE_HTTP_USERAGENT_TAG, user_agent) if user_agent
          rescue => e
            Datadog::AIGuard.telemetry&.report(e, description: "AI Guard: failed to get request attributes")
          end
          # steep:ignore:end

          # steep:ignore:start
          def clean_up_ai_guard_temp_tags!(trace)
            Ext::TRACE_ANOMALY_DETECTION_TAGS.each do |tag|
              trace.clear_tag(tag)
            end

            trace.clear_tag(Datadog::AIGuard::Ext::TRACE_EXECUTED_TAG)
          end
          # steep:ignore:end

          # AI Guard's evaluation flow sets `_dd.ai_guard.executed` on the
          # trace whenever an AI Guard span is created during the request.
          # steep:ignore:start
          def ai_guard_executed?(trace)
            trace.get_tag(Datadog::AIGuard::Ext::TRACE_EXECUTED_TAG) == "1"
          end
          # steep:ignore:end

          # steep:ignore:start
          def tag_client_ip_on_request_span!(trace)
            span = Datadog::Tracing.active_span
            return unless span

            client_ip = trace.get_tag(Datadog::AIGuard::Ext::TRACE_HTTP_CLIENT_IP_TAG)
            if client_ip && span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP).nil?
              span.set_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, client_ip)
            end

            network_client_ip = trace.get_tag(Datadog::AIGuard::Ext::TRACE_NETWORK_CLIENT_IP_TAG)
            span["network.client.ip"] = network_client_ip if network_client_ip
          rescue => e
            Datadog::AIGuard.telemetry&.report(e, description: "AI Guard: failed to tag client IP on root span")
          end
          # steep:ignore:end
        end
      end
    end
  end
end
