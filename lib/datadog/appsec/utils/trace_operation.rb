# frozen_string_literal: true

module Datadog
  module AppSec
    module Utils
      # Utility class to to AppSec-specific trace operations
      class TraceOperation
        def self.appsec_standalone_reject?(trace)
          !Datadog.configuration.tracing.apm.enabled &&
            (trace.nil? || trace.get_tag(Datadog::AppSec::Ext::TAG_DISTRIBUTED_APPSEC_EVENT) != '1')
        end
      end
    end
  end
end
