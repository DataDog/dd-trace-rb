# frozen_string_literal: true

module Datadog
  module AppSec
    # This class is used to mark trace as manual keep and tag it as ASM product.
    module TraceKeeper
      def self.keep!(trace)
        return unless trace

        # NOTE: This action will not set correct decision maker value, so the
        #       trace keeping must be done with additional steps below
        trace.keep!

        # Propagate to downstream services the information that
        # the current distributed trace is containing at least one ASM event.
        trace.set_tag(
          Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
          Tracing::Sampling::Ext::Decision::ASM
        )
        trace.set_distributed_source(Ext::PRODUCT_BIT)
      end
    end
  end
end
