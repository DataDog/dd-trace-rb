# frozen_string_literal: true

require "set"

require_relative "../../sampling/ext"

module Datadog
  module Tracing
    module Distributed
      class TraceState
        module Ext
          TRACESTATE_MAX_SIZE_LIMIT = 512
          TRACESTATE_MAX_LIST_VENDORS = 32
          TRACESTATE_VALUE_SIZE_LIMIT = 256

          module Datadog
            # ASCII characters 32-126, except `,`, `=`, and ` `. At least one character.
            VALID_KEY_CHARS = /\A(?:(?![,= ])[\u0020-\u007E])+\Z/.freeze
            # ASCII characters 32-126, except `,`. At least one character.
            VALID_VALUE_CHARS = /\A(?:(?!,)[\u0020-\u007E])+\Z/.freeze
            INVALID_ORIGIN_CHARS = /[\u0000-\u0019,;~\u007F-\u{10FFFF}]/.freeze
            REMAP_ORIGIN_CHARS = /=/.freeze
            INVALID_TAG_KEY_CHARS = /[\u0000-\u0020,=\u007F-\u{10FFFF}]/.freeze
            INVALID_TAG_VALUE_CHARS = /[\u0000-\u001F,;\u007E-\u{10FFFF}]/.freeze
          end

          module OpenTelemetry
            MAX_THRESHOLD = 1 << 56
            MAX_ENCODABLE_THRESHOLD = MAX_THRESHOLD - 1
            UINT64_MODULO = 1 << 64
            UINT64_MASK = UINT64_MODULO - 1
            VALID_THRESHOLD = /\A[0-9a-f]{1,14}\z/
            VALID_RANDOM_VALUE = /\A[0-9a-f]{14}\z/
            NON_PROBABILITY_DECISIONS = Set[
              Sampling::Ext::Decision::MANUAL,
              Sampling::Ext::Decision::ASM,
              Sampling::Ext::Decision::AI_GUARD,
            ].freeze
          end
        end
      end
    end
  end
end
