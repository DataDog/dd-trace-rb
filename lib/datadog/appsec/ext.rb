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

      TAG_APPSEC_ENABLED = '_dd.appsec.enabled'
      TAG_DISTRIBUTED_APPSEC_EVENT = '_dd.p.appsec'

      TELEMETRY_METRICS_NAMESPACE = 'appsec'
    end
  end
end
