# frozen_string_literal: true

module Datadog
  module AppSec
    module Ext
      INTERRUPT = :datadog_appsec_interrupt
      CONTEXT_KEY = 'datadog.appsec.context'
      ACTIVE_CONTEXT_KEY = :datadog_appsec_active_context

      TAG_APPSEC_ENABLED = '_dd.appsec.enabled'
      TAG_APM_ENABLED = '_dd.apm.enabled'
      TAG_DISTRIBUTED_APPSEC_EVENT = '_dd.p.appsec'
    end
  end
end
