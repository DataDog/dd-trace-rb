# frozen_string_literal: true

module Datadog
  module AppSec
    module Ext
      INTERRUPT = :datadog_appsec_interrupt
      SCOPE_KEY = 'datadog.appsec.scope'

      TAG_APPSEC_ENABLED = '_dd.appsec.enabled'
      TAG_APM_ENABLED = '_dd.apm.enabled'
      TAG_DISTRIBUTED_APPSEC_EVENT = '_dd.p.appsec'
    end
  end
end
