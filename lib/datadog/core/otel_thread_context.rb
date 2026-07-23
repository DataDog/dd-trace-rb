# frozen_string_literal: true

module Datadog
  module Core
    # Publishes a per-thread OpenTelemetry context record (trace id, span id) into a
    # thread-local slot, so an out-of-process reader (e.g. the eBPF profiler) can discover it.
    # See the "OTel Thread Context" OTEP (open-telemetry/opentelemetry-specification#4947).
    #
    # APIs in this module are implemented as native code; see ext/libdatadog_api/otel_thread_ctx.c.
    # Linux-only: `supported?` is `false` everywhere else.
    module OTelThreadContext
      class << self
        def supported?
          Datadog::Core::LIBDATADOG_API_FAILURE.nil? && _native_supported?
        end

        def enable!
          return false unless supported?

          _native_enable
        end

        def set(trace_id:, span_id:, local_root_span_id:)
          _native_set(trace_id, span_id, local_root_span_id)
        end

        def read
          raw = _native_read
          return unless raw

          attrs = decode_attrs(raw[:attrs])

          {
            trace_id: raw[:trace_id].unpack1("H*").to_s.to_i(16),
            span_id: raw[:span_id].unpack1("H*").to_s.to_i(16),
            local_root_span_id: attrs[0]&.to_i(16),
            valid: raw[:valid].getbyte(0) == 1,
            attrs: attrs
          }
        end

        private

        def decode_attrs(raw_attrs)
          attrs = {}
          offset = 0
          size = raw_attrs.bytesize

          while offset + 2 <= size
            key_index = raw_attrs.getbyte(offset)
            value_len = raw_attrs.getbyte(offset + 1)
            break unless key_index && value_len
            break if offset + 2 + value_len > size

            attrs[key_index] = raw_attrs.byteslice(offset + 2, value_len)
            offset += 2 + value_len
          end

          attrs
        end
      end
    end
  end
end
