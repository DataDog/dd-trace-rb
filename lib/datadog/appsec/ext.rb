# frozen_string_literal: true

module Datadog
  module AppSec
    module Ext
      RASP_SQLI = 'sql_injection'
      RASP_LFI = 'lfi'
      RASP_SSRF = 'ssrf'

      INTERRUPT = :datadog_appsec_interrupt
      CONTEXT_KEY = 'datadog.appsec.context'
      ACTIVE_CONTEXT_KEY = :datadog_appsec_active_context
      EXPLOIT_PREVENTION_EVENT_CATEGORY = 'exploit'

      TAG_APPSEC_ENABLED = '_dd.appsec.enabled'
      TAG_APM_ENABLED = '_dd.apm.enabled'
      TAG_DISTRIBUTED_APPSEC_EVENT = '_dd.p.appsec'
      TAG_METASTRUCT_STACK_TRACE = '_dd.stack'

      TELEMETRY_METRICS_NAMESPACE = 'appsec'
    end
  end
end
