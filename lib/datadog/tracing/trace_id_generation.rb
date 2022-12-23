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

        low_order  = Tracing::Utils.next_id
        high_order = Tracing::Utils.next_id

        if Datadog.configuration.tracing.trace_id_128_bit_propagation_enabled
          set_tag(Tracing::Metadata::Ext::Distributed::TAG_TID, high_order.to_s(16))
        end

        Tracing::Utils::TraceId.concatenate(high_order, low_order)
      end
    end
  end
end
