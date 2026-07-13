# frozen_string_literal: true

require 'set'
require 'json'

require_relative 'codec'

module Datadog
  module OpenFeature
    module Hooks
      class SpanEnrichmentHook
        # Per-root-span accumulator. Enforces the frozen limits, dedupes serial
        # ids structurally via a Set, and renders the three `ffe_*` tag shapes.
        #
        # Not internally synchronized: every method is only ever called while the
        # owning `SpanEnrichmentHook`'s mutex is held (capture, encode, cleanup),
        # so the accumulator stays a plain object and the lock provides the
        # consistent snapshot at encode time.
        class Accumulator
          def initialize
            @serial_ids = Set.new
            @subjects = {} # sha256hex => Set<int>
            @defaults = {} # flag_key => String
          end

          def add_serial_id(serial_id)
            return if @serial_ids.size >= MAX_SERIAL_IDS

            @serial_ids.add(serial_id)
          end

          def add_subject(targeting_key, serial_id)
            hashed = Codec.hash_targeting_key(targeting_key)
            existing = @subjects[hashed]

            if existing
              return if existing.size >= MAX_EXPERIMENTS_PER_SUBJECT

              existing.add(serial_id)
            elsif @subjects.size >= MAX_SUBJECTS
              nil
            else
              @subjects[hashed] = Set[serial_id]
            end
          end

          def add_default(flag_key, value)
            return if @defaults.key?(flag_key) # first-wins
            return if @defaults.size >= MAX_DEFAULTS

            value_str = value.is_a?(String) ? value : JSON.generate(value)
            # Truncate to the frozen 64-char cap. Slicing is by codepoint, so a
            # multibyte UTF-8 character is never split; `|| value_str` keeps the
            # value non-nil for the zero-start slice.
            @defaults[flag_key] = value_str[0, MAX_DEFAULT_VALUE_LENGTH] || value_str
          end

          # Subjects are intentionally not checked: a subject is only ever added
          # alongside a serial id, so serial ids cover that case.
          def has_data?
            @serial_ids.any? || @defaults.any?
          end

          def to_span_tags
            tags = {}
            tags[TAG_FLAGS_ENC] = Codec.encode_delta_varint(@serial_ids) unless @serial_ids.empty?

            unless @subjects.empty?
              encoded_subjects = {}
              @subjects.each { |hashed, ids| encoded_subjects[hashed] = Codec.encode_delta_varint(ids) }
              tags[TAG_SUBJECTS_ENC] = JSON.generate(encoded_subjects)
            end

            tags[TAG_RUNTIME_DEFAULTS] = JSON.generate(@defaults) unless @defaults.empty?

            tags
          end
        end
      end
    end
  end
end
