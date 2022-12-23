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
        Tracing::Utils.next_id.tap do
          if Datadog.configuration.tracing.trace_id_128_bit_generation_enabled
            set_tag(Tracing::Metadata::Ext::Distributed::TAG_TID, Tracing::Utils.next_id.to_s(16))
          end
        end
      end
    end
  end
end
