# frozen_string_literal: true

module Datadog
  module AppSec
    module Utils
      # Utility class to to AppSec-specific trace operations
      class TraceOperation
        # When APM is running in 'non-billing' mode, we should skip distributed tracing
        # unless specific distributed tags are present. These tags can come from upstream
        # services, or from the service itself.
        # For now, only '_dd.p.appsec=1' is supported.
        def self.appsec_standalone_reject?(trace)
          !Datadog.configuration.tracing.apm.enabled &&
            (trace.nil? || trace.get_tag(Datadog::AppSec::Ext::TAG_DISTRIBUTED_APPSEC_EVENT) != '1')
        end
      end
    end
  end
end
