# frozen_string_literal: true

module Datadog
  module AppSec
    # This class is used to mark trace as manual keep and tag it as ASM product.
    module TraceKeeper
      def self.keep!(trace)
        return unless trace

        previous_dm = trace.get_tag(Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER)

        # NOTE: This action will not set correct decision maker value, so the
        #       trace keeping must be done with additional steps below
        trace.keep!

        # NOTE: Preserve decision maker if already set by another product.
        #       As `trace.keep!` resets `_dd.p.dm` to `MANUAL`, we restore the
        #       previous value when another product has already claimed the
        #       decision maker.
        if previous_dm.nil? || previous_dm == Tracing::Sampling::Ext::Decision::MANUAL
          trace.set_tag(
            Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
            Tracing::Sampling::Ext::Decision::ASM
          )
        else
          trace.set_tag(
            Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
            previous_dm,
          )
        end

        trace.set_distributed_source(Ext::PRODUCT_BIT)
      end
    end
  end
end
