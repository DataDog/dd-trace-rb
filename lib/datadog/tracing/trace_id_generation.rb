# frozen_string_literal: true

# typed: ignore

require_relative 'utils'
require_relative 'metadata/tagging'
require_relative 'metadata/ext'

module Datadog
  module Tracing
    # The module contains logic about how trace id being generated,
    # it could be 64 bits or 128 bits, based on the configuration.
    module TraceIdGeneration
      def self.included(base)
        base.include Tracing::Metadata::Tagging
      end

      def generate_trace_id
        return Tracing::Utils.next_id unless Datadog.configuration.tracing.trace_id_128_bit_generation_enabled

        high_order = Tracing::Utils.next_id
        low_order  = Tracing::Utils.next_id

        # tag with hex encoded high order
        if Datadog.configuration.tracing.trace_id_128_bit_propagation_enabled
          set_tags(Tracing::Metadata::Ext::Distributed::TAG_TID => high_order.to_s(16))
        end

        Tracing::Utils::TraceId.concatenate(high_order, low_order)
      end
    end
  end
end
