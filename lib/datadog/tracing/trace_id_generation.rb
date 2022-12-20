# frozen_string_literal: true

# typed: ignore

require_relative 'utils'
require_relative 'metadata/tagging'
require_relative 'metadata/ext'

module Datadog
  module Tracing
    module TraceIdGeneration
      def self.included(base)
        base.include Tracing::Metadata::Tagging
      end

      def generate_trace_id
        if generation_enabled?
          high_order = Tracing::Utils.next_id
          low_order  = Tracing::Utils.next_id

          # tag with hex encoded high order
          if propagation_enabled?
            set_tags(Tracing::Metadata::Ext::Distributed::TAG_TID => high_order.to_s(16))
          end

          # high_order + low_order
          high_order << 64 | low_order
        else
          Tracing::Utils.next_id
        end
      end

      def generation_enabled?
        Datadog.configuration.tracing.trace_id_128_bit_generation_enabled
      end

      def propagation_enabled?
        Datadog.configuration.tracing.trace_id_128_bit_propagation_enabled
      end

      # def logging_enabled?
      #   Datadog.configuration.tracing.trace_id_128_bit_logging_enabled
      # end
    end
  end
end
