# frozen_string_literal: true

module Datadog
  module Tracing
    module Distributed
      # Helper method to decide when to skip distributed tracing
      module SkipPolicy
        module_function

        # Skips distributed tracing if disabled for this instrumentation
        # or if APM is disabled unless there is an upstream event (any _dd.p.ts value different than 0)
        def skip?(pin_config: nil, global_config: nil, trace: nil)
          unless ::Datadog.configuration.apm.tracing.enabled
            return true if trace.nil? || !::Datadog.configuration.appsec.enabled

            # If AppSec is enabled and AppSec bit is set in the trace, we should not skip distributed tracing
            # nil.to_i(16) will raise an error, so we use '0' as fallback
            appsec_bit =
              (trace.get_tag(Tracing::Metadata::Ext::Distributed::TAG_TRACE_SOURCE) || '0').to_i(16) &
              ::Datadog::AppSec::Ext::PRODUCT_BIT_APPSEC

            return true if appsec_bit == 0
          end

          return !pin_config[:distributed_tracing] if pin_config && pin_config.key?(:distributed_tracing)
          return !global_config[:distributed_tracing] if global_config

          false
        end
      end
    end
  end
end
