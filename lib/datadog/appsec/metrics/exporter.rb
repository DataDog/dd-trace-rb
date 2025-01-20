# frozen_string_literal: true

module Datadog
  module AppSec
    module Metrics
      # A class responsible for exporting WAF and RASP call metrics.
      module Exporter
        module_function

        def export_from(context)
          return if context.span.nil?

          export_waf_metrics(context.metrics.waf, context.span)
          export_rasp_metrics(context.metrics.rasp, context.span)
        end

        def export_waf_metrics(metrics, span)
          return if metrics.evals.zero?

          # expected time is in us
          span.set_tag('_dd.appsec.waf.timeouts', metrics.timeouts)
          span.set_tag('_dd.appsec.waf.duration', metrics.duration_ns / 1000.0)
          span.set_tag('_dd.appsec.waf.duration_ext', metrics.duration_ext_ns / 1000.0)
        end

        def export_rasp_metrics(metrics, span)
          return if metrics.evals.zero?

          span.set_tag('_dd.appsec.rasp.rule.eval', metrics.evals)
          span.set_tag('_dd.appsec.rasp.timeout', 1) unless metrics.timeouts.zero?
          span.set_tag('_dd.appsec.rasp.duration', metrics.duration_ns / 1000.0)
          span.set_tag('_dd.appsec.rasp.duration_ext', metrics.duration_ext_ns / 1000.0)
        end
      end
    end
  end
end
