# frozen_string_literal: true

require_relative "../../../tracing/client_ip"
require_relative "../../../tracing/contrib/rack/header_collection"
require_relative "../../../tracing/metadata/ext"

module Datadog
  module AIGuard
    module Contrib
      module Rack
        # Topmost AI Guard Rack middleware. Inserted just below
        # Datadog::Tracing::Contrib::Rack::TraceMiddleware, it tags the
        # local root (request) span with client IP information whenever
        # AI Guard is enabled, so any AI Guard span fired during the request
        # has these tags reachable from the service entry span.
        class RequestMiddleware
          NETWORK_CLIENT_IP_TAG = "network.client.ip"

          def initialize(app, opt = {})
            @app = app
          end

          def call(env)
            tag_client_ip(env)

            @app.call(env)
          end

          private

          def tag_client_ip(env)
            return unless Datadog::AIGuard.enabled?

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
