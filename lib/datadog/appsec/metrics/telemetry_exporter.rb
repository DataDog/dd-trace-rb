# frozen_string_literal: true

module Datadog
  module AppSec
    module Metrics
      # A class responsible for exporting WAF request metrics via Telemetry.
      module TelemetryExporter
        module_function

        def export_waf_request_metrics(waf_metrics, context)
          AppSec.telemetry.inc(
            Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
            tags: {
              waf_version: WAF::VERSION::BASE_STRING,
              event_rules_version: context.ruleset_version,
              rule_triggered: waf_metrics.matches.positive?.to_s,
              waf_error: waf_metrics.errors.positive?.to_s,
              waf_timeout: waf_metrics.timeouts.positive?.to_s,
              request_blocked: context.interrupted?.to_s,
              block_failure: 'false',
              rate_limited: (!context.trace.sampled?).to_s
            }
          )
        end
      end
    end
  end
end
