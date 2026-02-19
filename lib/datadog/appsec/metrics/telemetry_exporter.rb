# frozen_string_literal: true

module Datadog
  module AppSec
    module Metrics
      # A class responsible for exporting WAF request metrics via Telemetry.
      module TelemetryExporter
        module_function

        def export_waf_request_metrics(metrics, context)
          AppSec.telemetry.inc(
            Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
            tags: {
              waf_version: WAF::VERSION::BASE_STRING,
              event_rules_version: context.waf_runner_ruleset_version,
              rule_triggered: metrics.matches.positive?.to_s,
              waf_error: metrics.errors.positive?.to_s,
              waf_timeout: metrics.timeouts.positive?.to_s,
              request_blocked: context.interrupted?.to_s,
              block_failure: 'false',
              rate_limited: (!context.trace.sampled?).to_s,
              input_truncated: metrics.inputs_truncated.positive?.to_s,
            }
          )
        end

        def export_api_security_metrics(context)
          web_framework = context.state[:web_framework]
          return unless web_framework

          if context.span&.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE).nil?
            AppSec.telemetry.inc(
              AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'api_security.missing_route', 1,
              tags: {framework: web_framework}
            )
          end

          metric_name = context.state[:schema_extracted] ? 'schema' : 'no_schema'
          AppSec.telemetry.inc(
            AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, "api_security.request.#{metric_name}", 1,
            tags: {framework: web_framework}
          )
        end

        def export_user_auth_metrics(context)
          user_auth = context.state[:user_auth]
          return unless user_auth

          tags = {event_type: user_auth[:event].to_s, framework: user_auth[:framework].to_s}

          if user_auth[:login].nil?
            AppSec.telemetry.inc(
              AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_login', 1, tags: tags
            )

            if user_auth[:id].nil?
              AppSec.telemetry.inc(
                AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_id', 1, tags: tags
              )
            end
          end
        end
      end
    end
  end
end
