# frozen_string_literal: true

module Datadog
  module Tracing
    module Distributed
      # Helper method to decide when to skip distributed tracing
      module SkipPolicy
        module_function

        # Skips distributed tracing if disabled for this instrumentation
        # or if APM is disabled unless there is an AppSec event (from upstream distributed trace or local)
        def skip?(contrib_client_config: nil, contrib_datadog_config: nil, trace: nil)
          if ::Datadog.configuration.appsec.standalone.enabled &&
              (trace.nil? || trace.get_tag(::Datadog::AppSec::Ext::TAG_DISTRIBUTED_APPSEC_EVENT) != '1')
            return true
          end

          if contrib_client_config && contrib_client_config.key?(:distributed_tracing)
            return !contrib_client_config[:distributed_tracing]
          end
          return !contrib_datadog_config[:distributed_tracing] if contrib_datadog_config

          false
        end
      end
    end
  end
end
