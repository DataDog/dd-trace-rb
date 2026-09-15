# frozen_string_literal: true

require "json"

require_relative "../../../core/header_collection"
require_relative "../../../tracing/client_ip"
require_relative "../../default_header_tags"

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        # Applies AppSec request and response metadata to the Lambda invocation span.
        module Tagging
          module_function

          def tag_request(request, context:)
            span = context.span
            return unless span

            headers = Core::HeaderCollection.from_hash(request.headers)
            DefaultHeaderTags.tag_request(span, headers)
            return if span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP)

            Tracing::ClientIp.set_client_ip_tag!(span, headers: headers, remote_ip: request.remote_addr)
          end

          def tag_response(response, context:)
            span = context.span
            return unless span

            headers = Core::HeaderCollection.from_hash(response.headers)
            DefaultHeaderTags.tag_response(span, headers)
            return if headers.get("content-length")
            return unless response.body.respond_to?(:bytesize)

            span.set_tag("http.response.headers.content-length", response.body.bytesize.to_s)
          end

          def tag_and_keep(context, cold_start:)
            span = context.span
            trace = context.trace
            return unless trace && span

            span.set_metric(Ext::TAG_APPSEC_ENABLED, 1)
            span.set_tag("_dd.runtime_family", "ruby")
            span.set_tag("_dd.appsec.waf.version", WAF::VERSION::BASE_STRING)
            return unless context.waf_runner_ruleset_version

            span.set_tag("_dd.appsec.event_rules.version", context.waf_runner_ruleset_version)
            return unless cold_start

            trace.keep!
            trace.set_tag(
              Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
              Tracing::Sampling::Ext::Decision::ASM,
            )
            span.set_tag("_dd.appsec.event_rules.addresses", JSON.dump(context.waf_runner_known_addresses))
          end
        end
      end
    end
  end
end
