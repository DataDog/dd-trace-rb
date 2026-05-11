# frozen_string_literal: true

module Datadog
  module AppSec
    module Metrics
      # A class responsible for reporting WAF and RASP telemetry metrics.
      module Telemetry
        ACTION_BLOCK = 'block_request'
        ACTION_REDIRECT = 'redirect_request'
        BLOCK_SUCCESS = 'success'
        BLOCK_IRRELEVANT = 'irrelevant'

        module_function

        def report_rasp(type, result, phase: nil)
          return if result.error?

          tags = {rule_type: type, waf_version: WAF::VERSION::BASE_STRING}
          tags[:rule_variant] = phase if phase

          context = AppSec.active_context
          tags[:event_rules_version] = context.waf_runner_ruleset_version if context

          namespace = Ext::TELEMETRY_METRICS_NAMESPACE

          AppSec.telemetry.inc(namespace, 'rasp.rule.eval', 1, tags: tags)
          AppSec.telemetry.inc(namespace, 'rasp.timeout', 1, tags: tags) if result.timeout?

          if result.match?
            blocked = result.actions.key?(ACTION_BLOCK) || result.actions.key?(ACTION_REDIRECT)
            # NOTE: Mutates tags to avoid an extra hash allocation. Keep this the last .inc call.
            tags[:block] = blocked ? BLOCK_SUCCESS : BLOCK_IRRELEVANT

            AppSec.telemetry.inc(namespace, 'rasp.rule.match', 1, tags: tags)
          end
        end
      end
    end
  end
end
