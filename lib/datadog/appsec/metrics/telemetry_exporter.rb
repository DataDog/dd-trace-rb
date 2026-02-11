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
          return unless context.state[:instrumented_web_framework]

          metric_name = context.state[:schema_extracted] ? 'schema' : 'no_schema'

          AppSec.telemetry.inc(
            AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, "api_security.request.#{metric_name}", 1,
            tags: {framework: context.state[:instrumented_web_framework]}
          )
        end
      end
    end
  end
end
